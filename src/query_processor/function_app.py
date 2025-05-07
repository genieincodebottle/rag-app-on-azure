import logging
import os
import json
import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.cosmos import CosmosClient
from google import genai
from google.genai import types
from typing import List, Dict, Any
import numpy as np

# ENV setup
STAGE = os.environ.get("STAGE", "dev")
COSMOS_SECRET_URI = os.environ.get("COSMOS_SECRET_URI")  # format: <vault-url>|<secret-name>
GEMINI_SECRET_URI = os.environ.get("GEMINI_SECRET_URI")
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "models/gemini-pro")
GEMINI_EMBEDDING_MODEL = os.environ.get("GEMINI_EMBEDDING_MODEL")
TEMPERATURE = float(os.environ.get("TEMPERATURE", 0.2))
TOP_K = int(os.environ.get("TOP_K", 5))
TOP_P = float(os.environ.get("TOP_P", 1.0))
MAX_OUTPUT_TOKENS = int(os.environ.get("MAX_OUTPUT_TOKENS", 512))

# Credential setup
def get_secret(secret_uri: str) -> str:
    vault_url, secret_name = secret_uri.split("|")
    credential = DefaultAzureCredential()
    client = SecretClient(vault_url=vault_url, credential=credential)
    return client.get_secret(secret_name).value

# Gemini client init
GEMINI_API_KEY = get_secret(GEMINI_SECRET_URI)
client = genai.Client(api_key=GEMINI_API_KEY)

# Cosine similarity
def vector_similarity(a: List[float], b: List[float]) -> float:
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))

# Embedding from Gemini
def embed_query(text: str) -> List[float]:
    try:
        result = client.embed_content(
            model=GEMINI_EMBEDDING_MODEL,
            contents=text,
            config=types.EmbedContentConfig(task_type="SEMANTIC_SIMILARITY")
        )
        return list(result.embeddings[0].values)
    except Exception as e:
        logging.error(f"Gemini embedding failed: {str(e)}")
        return [0.0] * 768

# Fetch relevant chunks from Cosmos
def fetch_top_chunks(query_embedding: List[float], user_id: str, limit: int = 5):
    conn_str = get_secret(COSMOS_SECRET_URI)
    cosmos_client = CosmosClient.from_connection_string(conn_str)
    container = cosmos_client.get_database_client("ragdb").get_container_client("chunks")

    chunks = list(container.query_items(
        query="SELECT * FROM c WHERE c.user_id = @user_id",
        parameters=[{"name": "@user_id", "value": user_id}],
        enable_cross_partition_query=True
    ))

    for chunk in chunks:
        chunk["score"] = vector_similarity(query_embedding, chunk.get("embedding", [0.0]*768))

    sorted_chunks = sorted(chunks, key=lambda x: x["score"], reverse=True)[:limit]
    return sorted_chunks

# Gemini answer generation
def generate_response(query: str, context_chunks: List[Dict[str, Any]]) -> str:
    context = "\n\n".join([f"Document: {c.get('file_name', '')}\nContent: {c['content']}" for c in context_chunks])
    prompt = f"""
    Answer the following question based on the provided context.
    If the answer is not in the context, say "I don't have enough information."

    Context:
    {context}

    Question: {query}

    Answer:
    """
    try:
        result = client.generate_content(
            model=GEMINI_MODEL,
            contents=prompt,
            config=types.GenerateContentConfig(
                temperature=TEMPERATURE,
                top_k=TOP_K,
                top_p=TOP_P,
                max_output_tokens=MAX_OUTPUT_TOKENS
            )
        )
        return result.text
    except Exception as e:
        logging.error(f"Gemini response generation failed: {str(e)}")
        return "Sorry, I couldn't generate a response."

# Azure Function entrypoint
app = func.FunctionApp()

@app.function_name(name="query_processor")
@app.route(route="query", methods=["POST"])
def query_handler(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Query processor triggered.")
    try:
        body = req.get_json()
        user_id = body.get("user_id", "system")
        query = body.get("query")

        if not query:
            return func.HttpResponse(json.dumps({"error": "Query is required"}), status_code=400)

        query_embedding = embed_query(query)
        top_chunks = fetch_top_chunks(query_embedding, user_id)
        answer = generate_response(query, top_chunks)

        return func.HttpResponse(
            json.dumps({
                "query": query,
                "answer": answer,
                "context_used": [chunk["chunk_id"] for chunk in top_chunks],
                "count": len(top_chunks)
            }),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.exception("Query processing failed")
        return func.HttpResponse(json.dumps({"error": str(e)}), status_code=500)
