# src/query_processor/query_processor.py

"""
Azure Function to process queries and retrieve relevant documents using RAG.
"""
import os
import json
import logging
import azure.functions as func
from typing import List, Dict, Any
from decimal import Decimal

# Azure SDK imports
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.storage.blob import BlobServiceClient
from azure.cosmos import CosmosClient, PartitionKey
import psycopg2

# Gemini AI imports
from google import genai
from google.genai import types

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger()

# Environment variables
DOCUMENTS_CONTAINER = os.environ.get('DOCUMENTS_CONTAINER')
DOCUMENTS_STORAGE = os.environ.get('DOCUMENTS_STORAGE')
METADATA_COSMOS_ACCOUNT = os.environ.get('METADATA_COSMOS_ACCOUNT') 
METADATA_COSMOS_DATABASE = os.environ.get('METADATA_COSMOS_DATABASE')
METADATA_CONTAINER = os.environ.get('METADATA_CONTAINER')
STAGE = os.environ.get('STAGE')
DB_SECRET_URI = os.environ.get('DB_SECRET_URI')
GEMINI_SECRET_URI = os.environ.get('GEMINI_SECRET_URI')
GEMINI_MODEL = os.environ.get('GEMINI_MODEL')
GEMINI_EMBEDDING_MODEL = os.environ.get('GEMINI_EMBEDDING_MODEL')
TEMPERATURE = float(os.environ.get('TEMPERATURE', 0.2))
MAX_OUTPUT_TOKENS = int(os.environ.get('MAX_OUTPUT_TOKENS', 1024))
TOP_K = int(os.environ.get('TOP_K', 40))
TOP_P = float(os.environ.get('TOP_P', 0.8))

# Initialize Azure clients
credential = DefaultAzureCredential()

# Get Gemini API key from Key Vault
def get_gemini_api_key():
    try:
        # Parse URI to get Key Vault name and secret name
        parts = GEMINI_SECRET_URI.replace("https://", "").split('/')
        key_vault_name = parts[0].split('.')[0]
        secret_name = parts[-1]
        
        # Create a SecretClient
        secret_client = SecretClient(vault_url=f"https://{key_vault_name}.vault.azure.net/", credential=credential)
        
        # Get the secret
        secret = secret_client.get_secret(secret_name)
        credentials = json.loads(secret.value)
        return credentials['GEMINI_API_KEY']
    except Exception as e:
        logger.error(f"Error getting Gemini API key: {str(e)}")
        raise e

# Initialize Gemini client
try:
    GEMINI_API_KEY = get_gemini_api_key()
    client = genai.Client(api_key=GEMINI_API_KEY)
except Exception as e:
    logger.error(f"Error configuring Gemini API client: {str(e)}")
    raise

# Convert Decimal in Cosmos DB
class DecimalEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, Decimal):
            return float(o)
        return super().default(o)

# Embed a query using Gemini embedding model
def embed_query(text: str) -> List[float]:
    try:
        result = client.models.embed_content(
            model=GEMINI_EMBEDDING_MODEL,
            contents=text,
            config=types.EmbedContentConfig(task_type="SEMANTIC_SIMILARITY")
        )
        return list(result.embeddings[0].values)
    except Exception as e:
        logger.error(f"Error generating embedding: {str(e)}")
        return [0.0] * 768

# Embed a list of documents
def embed_documents(texts: List[str]) -> List[List[float]]:
    return [embed_query(text) for text in texts]

# Get PostgreSQL credentials from Key Vault
def get_postgres_credentials():
    try:
        # Parse URI to get Key Vault name and secret name
        parts = DB_SECRET_URI.replace("https://", "").split('/')
        key_vault_name = parts[0].split('.')[0]
        secret_name = parts[-1]
        
        # Create a SecretClient
        secret_client = SecretClient(vault_url=f"https://{key_vault_name}.vault.azure.net/", credential=credential)
        
        # Get the secret
        secret = secret_client.get_secret(secret_name)
        return json.loads(secret.value)
    except Exception as e:
        logger.error(f"Error getting PostgreSQL credentials: {str(e)}")
        raise e

# PostgreSQL connection
def get_postgres_connection(creds):
    return psycopg2.connect(
        host=creds['host'],
        port=creds['port'],
        user=creds['username'],
        password=creds['password'],
        dbname=creds['dbname']
    )

# Vector similarity search using pgvector
def similarity_search(query_embedding: List[float], user_id: str, limit: int = 5) -> List[Dict[str, Any]]:
    credentials = get_postgres_credentials()
    conn = get_postgres_connection(credentials)

    try:
        cursor = conn.cursor()

        # Manually convert the Python list to PostgreSQL vector string format
        vector_str = '[' + ','.join([str(x) for x in query_embedding]) + ']'

        cursor.execute(f"""
            SELECT 
                c.chunk_id,
                c.document_id,
                c.user_id,
                c.content,
                c.metadata,
                d.file_name,
                1 - (c.embedding <=> '{vector_str}'::vector) AS similarity_score
            FROM 
                chunks c
            JOIN 
                documents d ON c.document_id = d.document_id
            WHERE 
                c.user_id = %s
            ORDER BY 
                c.embedding <=> '{vector_str}'::vector
            LIMIT %s
        """, (user_id, limit))

        rows = cursor.fetchall()
        results = []
        for row in rows:
            chunk_id, document_id, user_id, content, metadata, file_name, similarity_score = row
            results.append({
                'chunk_id': chunk_id,
                'document_id': document_id,
                'user_id': user_id,
                'content': content,
                'metadata': metadata,
                'file_name': file_name,
                'similarity_score': float(similarity_score)
            })

        return results

    except Exception as e:
        logger.error(f"Similarity search failed: {str(e)}")
        raise e
    finally:
        cursor.close()
        conn.close()

# Generate a response from Gemini using relevant context
def generate_response(query: str, relevant_chunks: List[Dict[str, Any]]) -> str:
    context = "\n\n".join([f"Document: {c['file_name']}\nContent: {c['content']}" for c in relevant_chunks])
    prompt = f"""
    Answer the following question based on the provided context.
    If the answer is not in the context, say "I don't have enough information."

    Context:
    {context}

    Question: {query}

    Answer:
    """
    try:
        config = types.GenerateContentConfig(
            temperature=TEMPERATURE,
            top_p=TOP_P,
            top_k=TOP_K,
            max_output_tokens=MAX_OUTPUT_TOKENS,
            response_mime_type='application/json'
        )
        result = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=prompt,
            config=config
        )
        return result.text
    except Exception as e:
        logger.error(f"Failed to generate response: {str(e)}")
        return "Sorry, I couldn't generate a response. Please try again later."

# Azure Function entry point
def main(req: func.HttpRequest) -> func.HttpResponse:
    logger.info('Query processor function processed a request.')
    
    try:
        # Parse request body
        req_body = req.get_json()
        
        # Check if this is a health check request
        if req_body.get('action') == 'healthcheck':
            return func.HttpResponse(
                json.dumps({
                    'message': 'Query processor is healthy',
                    'stage': STAGE
                }),
                mimetype="application/json",
                status_code=200
            )
        
        query = req_body.get('query')
        user_id = req_body.get('user_id', 'system')
        
        if not query:
            return func.HttpResponse(
                json.dumps({
                    'message': 'Query is required'
                }),
                mimetype="application/json",
                status_code=400
            )
        
        query_embedding = embed_query(query)
        relevant_chunks = similarity_search(query_embedding, user_id)
        response = generate_response(query, relevant_chunks)
        
        return func.HttpResponse(
            json.dumps({
                'query': query,
                'response': response,
                'results': relevant_chunks,
                'count': len(relevant_chunks)
            }, cls=DecimalEncoder),
            mimetype="application/json",
            status_code=200
        )
        
    except Exception as e:
        logger.error(f"Unhandled error: {str(e)}")
        return func.HttpResponse(
            json.dumps({
                'message': f"Internal error: {str(e)}"
            }),
            mimetype="application/json",
            status_code=500
        )