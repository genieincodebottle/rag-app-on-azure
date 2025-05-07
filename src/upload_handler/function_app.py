import logging
import azure.functions as func
from azure.storage.blob import BlobServiceClient
from azure.cosmos import CosmosClient, exceptions
import os
import json
import base64
from datetime import datetime
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

app = func.FunctionApp()

# ENV variables
STAGE = os.environ.get("STAGE", "dev")
BLOB_CONNECTION_URI = os.environ.get("BLOB_SECRET_URI")  # <vault_uri>|<secret_name>
COSMOS_SECRET_URI = os.environ.get("COSMOS_SECRET_URI")  # <vault_uri>|<secret_name>
CONTAINER_NAME = os.environ.get("BLOB_CONTAINER", "documents")

def get_secret(secret_uri: str) -> str:
    vault_url, secret_name = secret_uri.split("|")
    credential = DefaultAzureCredential()
    client = SecretClient(vault_url=vault_url, credential=credential)
    return client.get_secret(secret_name).value

def upload_to_blob_storage(file_name, content):
    connection_string = get_secret(BLOB_CONNECTION_URI)
    blob_service_client = BlobServiceClient.from_connection_string(connection_string)
    blob_client = blob_service_client.get_blob_client(container=CONTAINER_NAME, blob=file_name)
    blob_client.upload_blob(content, overwrite=True)
    return blob_client.url

def store_metadata_to_cosmos(metadata):
    conn_str = get_secret(COSMOS_SECRET_URI)
    cosmos_client = CosmosClient.from_connection_string(conn_str)
    db = cosmos_client.get_database_client("ragdb")
    container = db.get_container_client("documents")
    container.upsert_item(metadata)

@app.function_name(name="upload_handler")
@app.route(route="upload", methods=["POST"])
def upload_handler(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Upload triggered.")
    try:
        body = req.get_json()
        user_id = body["user_id"]
        file_name = body["file_name"]
        mime_type = body["mime_type"]
        content = body["file_content"]
        decoded = base64.b64decode(content)

        timestamp = datetime.utcnow().isoformat()
        unique_id = f"{user_id}_{int(datetime.utcnow().timestamp())}"
        blob_url = upload_to_blob_storage(file_name, decoded)

        metadata = {
            "id": unique_id,
            "document_id": unique_id,
            "user_id": user_id,
            "file_name": file_name,
            "mime_type": mime_type,
            "status": "uploaded",
            "bucket": CONTAINER_NAME,
            "key": file_name,
            "url": blob_url,
            "created_at": timestamp,
            "updated_at": timestamp
        }

        store_metadata_to_cosmos(metadata)

        return func.HttpResponse(
            json.dumps({"message": "Upload successful", "document_id": unique_id}),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.exception("Upload failed")
        return func.HttpResponse(f"Error: {str(e)}", status_code=500)
