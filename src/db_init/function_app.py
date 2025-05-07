import logging
import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

import psycopg2
import socket
import os
import json
import time
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT

app = func.FunctionApp()

# Environment variables
STAGE = os.environ.get("STAGE", "dev")
MAX_RETRIES = int(os.environ.get("MAX_RETRIES", 5))
RETRY_DELAY = int(os.environ.get("RETRY_DELAY", 10))
DB_SECRET_URI = os.environ.get("DB_SECRET_URI")

def get_postgres_credentials():
    """
    Get PostgreSQL credentials from Azure Key Vault using DefaultAzureCredential.
    """
    try:
        vault_uri, secret_name = DB_SECRET_URI.split("|")
        credential = DefaultAzureCredential()
        client = SecretClient(vault_url=vault_uri, credential=credential)
        secret = client.get_secret(secret_name)
        return json.loads(secret.value)
    except Exception as e:
        logging.error(f"Error getting PostgreSQL credentials: {e}")
        raise

def check_dns_resolution(host):
    try:
        socket.gethostbyname(host)
        return True
    except socket.gaierror:
        return False

def create_database_if_not_exists(credentials, dbname, retry_count=0):
    host = credentials["host"]
    if not check_dns_resolution(host):
        if retry_count < MAX_RETRIES:
            time.sleep(RETRY_DELAY)
            return create_database_if_not_exists(credentials, dbname, retry_count + 1)
        return False

    try:
        conn = psycopg2.connect(
            host=host,
            port=credentials["port"],
            user=credentials["username"],
            password=credentials["password"],
            dbname="postgres",
            connect_timeout=10,
        )
        conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
        cur = conn.cursor()
        cur.execute(f"SELECT 1 FROM pg_database WHERE datname = '{dbname}'")
        if not cur.fetchone():
            cur.execute(f"CREATE DATABASE {dbname}")
        cur.close()
        conn.close()
        return True
    except Exception as e:
        logging.warning(f"Create DB Error: {e}")
        if retry_count < MAX_RETRIES:
            time.sleep(RETRY_DELAY)
            return create_database_if_not_exists(credentials, dbname, retry_count + 1)
        return False

def initialize_database(credentials, retry_count=0):
    host = credentials["host"]
    dbname = credentials["dbname"]

    if not check_dns_resolution(host):
        if retry_count < MAX_RETRIES:
            time.sleep(RETRY_DELAY)
            return initialize_database(credentials, retry_count + 1)
        return False

    try:
        conn = psycopg2.connect(
            host=host,
            port=credentials["port"],
            user=credentials["username"],
            password=credentials["password"],
            dbname=dbname,
            connect_timeout=10,
        )
        conn.autocommit = True
        cur = conn.cursor()

        cur.execute("CREATE EXTENSION IF NOT EXISTS vector")

        cur.execute("""
        CREATE TABLE IF NOT EXISTS documents (
            id SERIAL PRIMARY KEY,
            document_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            file_name TEXT NOT NULL,
            mime_type TEXT NOT NULL,
            status TEXT NOT NULL,
            bucket TEXT NOT NULL,
            key TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT NOW(),
            updated_at TIMESTAMP DEFAULT NOW()
        )""")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_documents_document_id ON documents(document_id)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_documents_user_id ON documents(user_id)")

        cur.execute("""
        CREATE TABLE IF NOT EXISTS chunks (
            id SERIAL PRIMARY KEY,
            chunk_id TEXT NOT NULL,
            document_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            content TEXT NOT NULL,
            metadata JSONB,
            embedding VECTOR(768),
            created_at TIMESTAMP DEFAULT NOW(),
            updated_at TIMESTAMP DEFAULT NOW()
        )""")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_chunks_document_id ON chunks(document_id)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_chunks_user_id ON chunks(user_id)")
        try:
            cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_chunks_embedding ON chunks
            USING ivfflat (embedding vector_cosine_ops)
            WITH (lists = 100)
            """)
        except Exception:
            cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_chunks_embedding ON chunks
            USING btree (embedding)
            """)

        cur.close()
        conn.close()
        return True
    except Exception as e:
        logging.error(f"Init DB Error: {e}")
        if retry_count < MAX_RETRIES:
            time.sleep(RETRY_DELAY)
            return initialize_database(credentials, retry_count + 1)
        return False

@app.function_name(name="db_init")
@app.route(route="db_init", methods=["POST"])
def run_db_init(req: func.HttpRequest) -> func.HttpResponse:
    logging.info(f"Initializing DB at stage: {STAGE}")

    try:
        body = req.get_json()
        if body.get("action") == "healthcheck":
            return func.HttpResponse(
                json.dumps({"message": "DB init healthy", "stage": STAGE}),
                mimetype="application/json"
            )

        credentials = get_postgres_credentials()
        if not create_database_if_not_exists(credentials, credentials["dbname"]):
            return func.HttpResponse("Failed to create database", status_code=500)
        if not initialize_database(credentials):
            return func.HttpResponse("Failed to initialize schema", status_code=500)

        return func.HttpResponse("Database initialization completed", status_code=200)

    except Exception as e:
        return func.HttpResponse(f"Error: {str(e)}", status_code=500)
