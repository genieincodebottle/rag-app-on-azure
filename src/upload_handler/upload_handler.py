# src/upload_handler/upload_handler.py

"""
Azure Function to handle document uploads.
"""
import os
import json
import logging
import azure.functions as func
import uuid
import base64
import psycopg2
from datetime import datetime

# Azure SDK imports
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.storage.blob import BlobServiceClient
from azure.cosmos import CosmosClient, PartitionKey

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

# Initialize Azure clients
credential = DefaultAzureCredential()

def get_postgres_credentials():
    """
    Get PostgreSQL credentials from Azure Key Vault.
    """
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

def get_postgres_connection(credentials):
    """
    Get a connection to PostgreSQL.
    """
    conn = psycopg2.connect(
        host=credentials['host'],
        port=credentials['port'],
        user=credentials['username'],
        password=credentials['password'],
        dbname=credentials['dbname']
    )
    return conn

def get_mime_type(file_name):
    """
    Determine MIME type from file extension.
    
    Args:
        file_name (str): File name
        
    Returns:
        str: MIME type
    """
    file_extension = file_name.split('.')[-1].lower()
    mime_types = {
        'pdf': 'application/pdf',
        'txt': 'text/plain',
        'csv': 'text/csv',
        'doc': 'application/msword',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls': 'application/vnd.ms-excel',
        'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'json': 'application/json',
        'md': 'text/markdown'
    }
    return mime_types.get(file_extension, 'application/octet-stream')

def main(req: func.HttpRequest) -> func.HttpResponse:
    """
    Azure Function to handle document uploads.
    
    Args:
        req (func.HttpRequest): HTTP request
        
    Returns:
        func.HttpResponse: HTTP response
    """
    logger.info('Upload handler function processed a request.')
    
    try:
        # Parse request body
        req_body = req.get_json()
        
        # Check if this is a health check request
        if req_body.get('action') == 'healthcheck':
            return func.HttpResponse(
                json.dumps({
                    'message': 'Upload handler is healthy',
                    'stage': STAGE
                }),
                mimetype="application/json",
                status_code=200
            )
        
        # Extract file data and metadata
        file_content_base64 = req_body.get('file_content', '')
        file_name = req_body.get('file_name', '')
        mime_type = req_body.get('mime_type', None)
        user_id = req_body.get('user_id', 'system')
        
        if not file_content_base64 or not file_name:
            return func.HttpResponse(
                json.dumps({
                    'message': 'File content and name are required'
                }),
                mimetype="application/json",
                status_code=400
            )
        
        # Determine MIME type if not provided
        if not mime_type:
            mime_type = get_mime_type(file_name)
            
        # Decode base64 content
        file_content = base64.b64decode(file_content_base64)
        
        # Generate a unique document ID
        document_id = str(uuid.uuid4())
        
        # Upload file to Blob Storage
        blob_path = f"uploads/{user_id}/{document_id}/{file_name}"
        
        # Initialize blob client
        blob_service_client = BlobServiceClient(
            account_url=f"https://{DOCUMENTS_STORAGE}.blob.core.windows.net",
            credential=credential
        )
        container_client = blob_service_client.get_container_client(DOCUMENTS_CONTAINER)
        blob_client = container_client.get_blob_client(blob_path)
        
        # Upload blob
        blob_client.upload_blob(file_content, overwrite=True, content_settings={
            "content_type": mime_type
        })
        
        # Store initial metadata in PostgreSQL
        try:
            # Get PostgreSQL credentials
            credentials = get_postgres_credentials()
            conn = get_postgres_connection(credentials)
            cursor = conn.cursor()
            
            # Insert document record
            cursor.execute("""
            INSERT INTO documents (document_id, user_id, file_name, mime_type, status, bucket, key, created_at, updated_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                document_id,
                user_id,
                file_name,
                mime_type,
                'uploaded',
                DOCUMENTS_CONTAINER,
                blob_path,
                datetime.now(),
                datetime.now()
            ))
            
            # Commit the transaction
            conn.commit()
            cursor.close()
            conn.close()
            
        except Exception as e:
            logger.error(f"Error storing metadata in PostgreSQL: {str(e)}")
            # Continue with Cosmos DB as fallback
        
        # Store metadata in Cosmos DB
        try:
            # Initialize Cosmos DB client
            cosmos_client = CosmosClient(
                url=f"https://{METADATA_COSMOS_ACCOUNT}.documents.azure.com:443/",
                credential=credential
            )
            database = cosmos_client.get_database_client(METADATA_COSMOS_DATABASE)
            container = database.get_container_client(METADATA_CONTAINER)
            
            # Store metadata
            metadata_item = {
                'id': f"doc#{document_id}",
                'document_id': document_id,
                'user_id': user_id,
                'file_name': file_name,
                'mime_type': mime_type,
                'status': 'uploaded',
                'container': DOCUMENTS_CONTAINER,
                'path': blob_path,
                'created_at': datetime.now().isoformat(),
                'updated_at': datetime.now().isoformat()
            }
            
            container.create_item(body=metadata_item)
            
        except Exception as e:
            logger.error(f"Error storing metadata in Cosmos DB: {str(e)}")
            # Continue since we already stored in PostgreSQL
        
        # Return success response
        return func.HttpResponse(
            json.dumps({
                'message': 'File uploaded successfully',
                'document_id': document_id,
                'file_name': file_name
            }),
            mimetype="application/json",
            status_code=200
        )
        
    except Exception as e:
        logger.error(f"Error uploading file: {str(e)}")
        return func.HttpResponse(
            json.dumps({
                'message': f"Error uploading file: {str(e)}"
            }),
            mimetype="application/json",
            status_code=500
        )