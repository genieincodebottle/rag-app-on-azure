import logging
import azure.functions as func
import os
import json
import openai
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from typing import List
from tenacity import retry, stop_after_attempt, wait_fixed
from sentence_transformers import SentenceTransformer
import numpy as np

app = func.FunctionApp()

# ENV variables
STAGE = os.environ.get("STAGE", "dev")
COSMOS_SECRET_URI = os.environ.get("COSMOS_SECRET_URI")  # <vault>|<secret>
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "all-MiniLM-L6-v2")

def get_secret(secret_uri: str) -> str:
    vault_url, secret_name = secret_uri.split("|")
    credential = DefaultAzureCredential()
    client = SecretClient(vault_url=vault_url, credential=credential)
    return client.get_secret(secret_name).value

def vector_similarity(a: List[float], b: List[float]) -> float:
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))

def fetch_top_chunks(query_embedding: List[float], user_id: str, limit: int = 5):
    conn_str = get_secret(COSMOS_SECRET_URI)
    cosmos_client = CosmosClient.from_connection_string(conn_str)
    db = cosmos_client.get_database_client("ragdb")
    container = db.get_container_client("chunks")

    all_chunks = list(container.query_items(
        query=f"SELECT * FROM c WHERE c.user_id = @user_id",
        parameters=[{"name": "@user_id", "value": user_id}],
        enable_cross_partition_query=True
    ))

    # Compute similarity manually
    for chunk in all_chunks:
        chunk["score"] = vector_similarity(query_embedding, chunk.get("embedding", [0]*768))

    sorted_chunks = sorted(all_chunks, key=lambda x: x["score"], reverse=True)[:limit]
    return sorted_chunks

def generate_response(context_text: str, query: str) -> str:
    prompt = f"""You are an assistant. Use the below context to answer the query.
Context:
{context_text}

Query: {query}
Answer:"""

    # Replace this with Gemini, Claude, or OpenAI API
    openai.api_key = os.getenv("OPENAI_API_KEY")
    response = openai.ChatCompletion.create(
        model="gpt-3.5-turbo",
        messages=[{"role": "user", "content": prompt}],
        temperature=0.2
    )
    return response.choices[0].message["content"]

@app.function_name(name="query_processor")
@app.route(route="query", methods=["POST"])
def query_handler(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Query processor triggered.")
    try:
        body = req.get_json()
        user_id = body["user_id"]
        question = body["query"]

        # Get embedding for query
        model = SentenceTransformer(EMBEDDING_MODEL)
        query_vec = model.encode(question).tolist()

        # Fetch top chunks
        top_chunks = fetch_top_chunks(query_vec, user_id)
        combined_context = "\n\n".join([chunk["content"] for chunk in top_chunks])

        answer = generate_response(combined_context, question)

        return func.HttpResponse(
            json.dumps({
                "answer": answer,
                "context_used": [chunk["chunk_id"] for chunk in top_chunks]
            }),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.exception("Query processing failed")
        return func.HttpResponse(f"Error: {str(e)}", status_code=500)
