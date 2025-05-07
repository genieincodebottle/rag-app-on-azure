import logging
import azure.functions as func
import os
import json
import tempfile
import urllib.parse
import uuid
from datetime import datetime
from PyPDF2 import PdfReader
from azure.storage.blob import BlobServiceClient
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain.schema import Document
from google import genai
from google.genai import types

# ENV
COSMOS_SECRET_URI = os.environ.get("COSMOS_SECRET_URI")
BLOB_SECRET_URI = os.environ.get("BLOB_SECRET_URI")
CONTAINER_NAME = os.environ.get("BLOB_CONTAINER", "documents")
GEMINI_SECRET_URI = os.environ.get("GEMINI_SECRET_URI")
GEMINI_MODEL = os.environ.get("GEMINI_EMBEDDING_MODEL")
STAGE = os.environ.get("STAGE", "dev")

TEMPERATURE = float(os.environ.get("TEMPERATURE", 0.2))
MAX_OUTPUT_TOKENS = int(os.environ.get("MAX_OUTPUT_TOKENS", 1024))
TOP_K = int(os.environ.get("TOP_K", 10))
TOP_P = float(os.environ.get("TOP_P", 0.95))

app = func.FunctionApp()

def get_secret(secret_uri: str) -> str:
    vault_url, secret_name = secret_uri.split("|")
    credential = DefaultAzureCredential()
    client = SecretClient(vault_url=vault_url, credential=credential)
    return client.get_secret(secret_name).value

# Init Gemini client
try:
    gemini_key = get_secret(GEMINI_SECRET_URI)
    client = genai.Client(api_key=gemini_key)
except Exception as e:
    logging.error(f"Gemini config failed: {e}")

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

def chunk_text(text):
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000,
        chunk_overlap=200,
        length_function=len,
        separators=["\n\n", "\n", " ", ""]
    )
    docs = splitter.create_documents([text])
    return docs

def embed_text(text: str):
    try:
        result = client.models.embed_content(
            model=GEMINI_MODEL,
            contents=text,
            config=types.EmbedContentConfig(task_type="SEMANTIC_SIMILARITY")
        )
        return list(result.embeddings[0].values)
    except Exception as e:
        logging.warning(f"Gemini embed error: {e}")
        return [0.0] * 768

def store_chunks(user_id, document_id, docs):
    conn_str = get_secret(COSMOS_SECRET_URI)
    cosmos_client = CosmosClient.from_connection_string(conn_str)
    container = cosmos_client.get_database_client("ragdb").get_container_client("chunks")
    now = datetime.utcnow().isoformat()

    for doc in docs:
        chunk = {
            "id": str(uuid.uuid4()),
            "chunk_id": str(uuid.uuid4()),
            "document_id": document_id,
            "user_id": user_id,
            "content": doc.page_content,
            "metadata": doc.metadata,
            "embedding": embed_text(doc.page_content),
            "created_at": now,
            "updated_at": now
        }
        container.upsert_item(chunk)

@app.function_name(name="document_processor")
@app.route(route="document", methods=["POST"])
def process_document(req: func.HttpRequest) -> func.HttpResponse:
    try:
        body = req.get_json()
        file_name = body["file_name"]
        user_id = body["user_id"]
        document_id = body.get("document_id", str(uuid.uuid4()))

        file_path = download_blob(file_name)
        text = extract_text_from_pdf(file_path)
        docs = chunk_text(text)
        store_chunks(user_id, document_id, docs)

        return func.HttpResponse(
            json.dumps({"message": "Document processed", "chunks_stored": len(docs)}),
            status_code=200,
            mimetype="application/json"
        )
    except Exception as e:
        logging.exception("Processing failed")
        return func.HttpResponse(f"Error: {str(e)}", status_code=500)
