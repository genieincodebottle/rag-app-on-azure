import logging
import azure.functions as func
import os
import json
import base64
import tempfile
from PyPDF2 import PdfReader
from azure.cosmos import CosmosClient
from azure.storage.blob import BlobServiceClient
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from datetime import datetime
from sentence_transformers import SentenceTransformer
import uuid

app = func.FunctionApp()

# ENV
COSMOS_SECRET_URI = os.environ.get("COSMOS_SECRET_URI")
BLOB_SECRET_URI = os.environ.get("BLOB_SECRET_URI")
CONTAINER_NAME = os.environ.get("BLOB_CONTAINER", "documents")
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "all-MiniLM-L6-v2")

def get_secret(secret_uri: str) -> str:
    vault_url, secret_name = secret_uri.split("|")
    credential = DefaultAzureCredential()
    client = SecretClient(vault_url=vault_url, credential=credential)
    return client.get_secret(secret_name).value

def download_blob(file_name):
    connection_string = get_secret(BLOB_SECRET_URI)
    blob_service_client = BlobServiceClient.from_connection_string(connection_string)
    blob_client = blob_service_client.get_blob_client(container=CONTAINER_NAME, blob=file_name)

    with tempfile.NamedTemporaryFile(delete=False) as temp:
        temp.write(blob_client.download_blob().readall())
        return temp.name

def extract_text_from_pdf(file_path):
    text = ""
    try:
        reader = PdfReader(file_path)
        for page in reader.pages:
            text += page.extract_text() or ""
        return text
    except Exception as e:
        logging.warning(f"PDF extract failed: {e}")
        return ""

def split_into_chunks(text, max_length=500):
    words = text.split()
    return [" ".join(words[i:i + max_length]) for i in range(0, len(words), max_length)]

def store_chunks(user_id, document_id, chunks):
    conn_str = get_secret(COSMOS_SECRET_URI)
    cosmos_client = CosmosClient.from_connection_string(conn_str)
    db = cosmos_client.get_database_client("ragdb")
    container = db.get_container_client("chunks")
    now = datetime.utcnow().isoformat()

    for chunk_text, embedding in chunks:
        chunk = {
            "id": str(uuid.uuid4()),
            "chunk_id": str(uuid.uuid4()),
            "document_id": document_id,
            "user_id": user_id,
            "content": chunk_text,
            "metadata": {},
            "embedding": embedding,
            "created_at": now,
            "updated_at": now
        }
        container.upsert_item(chunk)

@app.function_name(name="document_processor")
@app.route(route="document", methods=["POST"])
def process_document(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Document processing started.")
    try:
        body = req.get_json()
        file_name = body["file_name"]
        user_id = body["user_id"]
        document_id = body.get("document_id", str(uuid.uuid4()))

        file_path = download_blob(file_name)
        text = extract_text_from_pdf(file_path)
        chunks_raw = split_into_chunks(text)

        model = SentenceTransformer(EMBEDDING_MODEL)
        embeddings = model.encode(chunks_raw)

        chunks = list(zip(chunks_raw, embeddings.tolist()))
        store_chunks(user_id, document_id, chunks)

        return func.HttpResponse(
            json.dumps({"message": "Document processed", "chunks_stored": len(chunks)}),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.exception("Document processing failed")
        return func.HttpResponse(f"Error: {str(e)}", status_code=500)
