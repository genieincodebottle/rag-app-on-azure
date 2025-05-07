"""Test cases for the document_processor Azure Function."""
import json
import os
import unittest
from unittest.mock import MagicMock, patch
import tempfile

"""Set up test environment."""
# Set environment variables
os.environ["DOCUMENTS_CONTAINER"] = "test-container"
os.environ["DOCUMENTS_STORAGE"] = "teststorage"
os.environ["METADATA_COSMOS_ACCOUNT"] = "test-cosmos"
os.environ["METADATA_COSMOS_DATABASE"] = "test-db"
os.environ["METADATA_CONTAINER"] = "test-container"
os.environ["STAGE"] = "test"
os.environ["DB_SECRET_URI"] = "https://test-kv.vault.azure.net/secrets/db-credentials"
os.environ["GEMINI_SECRET_URI"] = "https://test-kv.vault.azure.net/secrets/gemini-api-key"
os.environ["GEMINI_EMBEDDING_MODEL"] = "test-embedding-model"
os.environ["TEMPERATURE"] = "0.2"
os.environ["MAX_OUTPUT_TOKENS"] = "1024"
os.environ["TOP_K"] = "40"
os.environ["TOP_P"] = "0.8"
os.environ["SIMILARITY_THRESHOLD"] = "0.7"

# Now import the module under test - mocks are already in place globally from conftest
from document_processor.function_app import (
    process_document, get_gemini_api_key, get_postgres_credentials, get_postgres_connection,
    embed_query, embed_documents, get_document_loader, chunk_documents, process_document
)

class TestDocumentProcessor(unittest.TestCase):
    """Test cases for the document_processor Azure Function."""

    def setUp(self):
        # Mock Azure clients
        self.blob_patcher = patch('document_processor.document_processor.BlobServiceClient')
        self.cosmos_patcher = patch("document_processor.document_processor.CosmosClient")
        self.secret_patcher = patch("document_processor.document_processor.SecretClient")
        self.credential_patcher = patch("document_processor.document_processor.DefaultAzureCredential")
        self.client_patcher = patch('document_processor.document_processor.client')
        
        self.mock_blob = self.blob_patcher.start()
        self.mock_cosmos = self.cosmos_patcher.start()
        self.mock_secret = self.secret_patcher.start()
        self.mock_credential = self.credential_patcher.start()
        self.mock_client = self.client_patcher.start()
        
        # Set up mock blob client
        self.mock_blob_service_client = MagicMock()
        self.mock_container_client = MagicMock()
        self.mock_blob_client = MagicMock()
        self.mock_container_client.get_blob_client.return_value = self.mock_blob_client
        self.mock_blob_service_client.get_container_client.return_value = self.mock_container_client
        self.mock_blob.return_value = self.mock_blob_service_client
        
        # Mock download_blob_to_file
        self.mock_blob_client.download_blob_to_file = MagicMock()

    def tearDown(self):
        """Clean up test environment."""
        # Clean up environment variables
        for key in [
            "DOCUMENTS_CONTAINER", "DOCUMENTS_STORAGE", "METADATA_COSMOS_ACCOUNT", 
            "METADATA_COSMOS_DATABASE", "METADATA_CONTAINER", "STAGE", "DB_SECRET_URI",
            "GEMINI_SECRET_URI", "GEMINI_EMBEDDING_MODEL", "TEMPERATURE",
            "MAX_OUTPUT_TOKENS", "TOP_K", "TOP_P", "SIMILARITY_THRESHOLD"
        ]:
            if key in os.environ:
                del os.environ[key]
                
        # Stop patchers
        self.blob_patcher.stop()
        self.cosmos_patcher.stop()
        self.secret_patcher.stop()
        self.credential_patcher.stop()
        self.client_patcher.stop()

    @patch("document_processor.document_processor.SecretClient")
    def test_get_gemini_api_key(self, mock_secret_client):
        """Test getting Gemini API key from Azure Key Vault."""
        # Mock the Key Vault response
        mock_secret = MagicMock()
        mock_secret.value = json.dumps({"GEMINI_API_KEY": "mock-api-key"})
        mock_client_instance = MagicMock()
        mock_client_instance.get_secret.return_value = mock_secret
        mock_secret_client.return_value = mock_client_instance

        # Call the function
        api_key = get_gemini_api_key()

        # Verify results
        self.assertEqual(api_key, "mock-api-key")
        mock_client_instance.get_secret.assert_called_once_with("gemini-api-key")
        
    @patch("document_processor.document_processor.SecretClient")
    def test_get_postgres_credentials(self, mock_secret_client):
        """Test getting PostgreSQL credentials from Azure Key Vault."""
        # Mock the Key Vault response
        mock_credentials = {
            "host": "test-host",
            "port": 5432,
            "username": "test-user",
            "password": "test-password",
            "dbname": "test-db"
        }
        mock_secret = MagicMock()
        mock_secret.value = json.dumps(mock_credentials)
        mock_client_instance = MagicMock()
        mock_client_instance.get_secret.return_value = mock_secret
        mock_secret_client.return_value = mock_client_instance

        # Call the function
        credentials = get_postgres_credentials()

        # Verify results
        self.assertEqual(credentials, mock_credentials)
        mock_client_instance.get_secret.assert_called_once_with("db-credentials")

    @patch("document_processor.document_processor.psycopg2")
    def test_get_postgres_connection(self, mock_psycopg2):
        """Test getting a PostgreSQL connection."""
        # Mock the psycopg2 connection
        mock_conn = MagicMock()
        mock_psycopg2.connect.return_value = mock_conn

        # Test credentials
        credentials = {
            "host": "test-host",
            "port": 5432,
            "username": "test-user",
            "password": "test-password",
            "dbname": "test-db"
        }

        # Call the function
        conn = get_postgres_connection(credentials)

        # Verify results
        self.assertEqual(conn, mock_conn)
        mock_psycopg2.connect.assert_called_once_with(
            host="test-host",
            port=5432,
            user="test-user",
            password="test-password",
            dbname="test-db"
        )

    @patch("document_processor.document_processor.client")
    def test_embed_query(self, mock_client):
        """Test embedding a query using Gemini."""
        # Mock the Gemini embedding response
        mock_embeddings = MagicMock()
        mock_embeddings.embeddings = [MagicMock()]
        mock_embeddings.embeddings[0].values = [0.1, 0.2, 0.3]
        mock_client.models.embed_content.return_value = mock_embeddings

        # Call the function
        result = embed_query("Test query")

        # Verify results
        self.assertEqual(result, [0.1, 0.2, 0.3])
        mock_client.models.embed_content.assert_called_once()

    @patch("document_processor.document_processor.embed_query")
    def test_embed_documents(self, mock_embed_query):
        """Test embedding multiple documents."""
        # Mock the embed_query function
        mock_embed_query.side_effect = [
            [0.1, 0.2, 0.3],
            [0.4, 0.5, 0.6]
        ]

        # Test documents
        docs = ["Document 1", "Document 2"]

        # Call the function
        result = embed_documents(docs)

        # Verify results
        self.assertEqual(result, [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]])
        self.assertEqual(mock_embed_query.call_count, 2)
        mock_embed_query.assert_any_call("Document 1")
        mock_embed_query.assert_any_call("Document 2")

    @patch("document_processor.document_processor.PyPDFLoader")
    def test_get_document_loader_pdf(self, mock_loader_class):
        """Test getting document loader for PDF files."""
        mock_loader = MagicMock()
        mock_loader_class.return_value = mock_loader
        
        loader = get_document_loader("test.pdf", "application/pdf")
        
        self.assertEqual(loader, mock_loader)
        mock_loader_class.assert_called_once_with("test.pdf")

    @patch("document_processor.document_processor.TextLoader")
    def test_get_document_loader_text(self, mock_loader_class):
        """Test getting document loader for text files."""
        mock_loader = MagicMock()
        mock_loader_class.return_value = mock_loader
        
        loader = get_document_loader("test.txt", "text/plain")
        
        self.assertEqual(loader, mock_loader)
        mock_loader_class.assert_called_once_with("test.txt")

    @patch("document_processor.document_processor.CSVLoader")
    def test_get_document_loader_csv(self, mock_loader_class):
        """Test getting document loader for CSV files."""
        mock_loader = MagicMock()
        mock_loader_class.return_value = mock_loader
        
        loader = get_document_loader("test.csv", "text/csv")
        
        self.assertEqual(loader, mock_loader)
        mock_loader_class.assert_called_once_with("test.csv")

    @patch("document_processor.document_processor.TextLoader")
    def test_get_document_loader_unknown(self, mock_loader_class):
        """Test getting document loader for unknown file types."""
        mock_loader = MagicMock()
        mock_loader_class.return_value = mock_loader
        
        loader = get_document_loader("test.unknown", "application/octet-stream")
        
        self.assertEqual(loader, mock_loader)
        mock_loader_class.assert_called_once_with("test.unknown")

    @patch("document_processor.document_processor.RecursiveCharacterTextSplitter")
    def test_chunk_documents(self, mock_splitter_class):
        """Test chunking documents."""
        # Mock the splitter
        mock_splitter = MagicMock()
        mock_splitter_class.return_value = mock_splitter
        
        # Mock the split_documents method
        mock_chunks = ["chunk1", "chunk2"]
        mock_splitter.split_documents.return_value = mock_chunks
        
        # Test documents
        docs = ["doc1", "doc2"]
        
        # Call the function
        result = chunk_documents(docs)
        
        # Verify results
        self.assertEqual(result, mock_chunks)
        mock_splitter_class.assert_called_once_with(
            chunk_size=1000,
            chunk_overlap=200,
            length_function=len,
            separators=["\n\n", "\n", " ", ""]
        )
        mock_splitter.split_documents.assert_called_once_with(docs)

    @patch("document_processor.document_processor.tempfile")
    @patch("document_processor.document_processor.get_document_loader")
    @patch("document_processor.document_processor.chunk_documents")
    @patch("document_processor.document_processor.embed_query")
    @patch("document_processor.document_processor.get_postgres_credentials")
    @patch("document_processor.document_processor.get_postgres_connection")
    @patch("document_processor.document_processor.os.unlink")
    @patch("document_processor.document_processor.uuid.uuid4")
    @patch("document_processor.document_processor.datetime")
    def test_process_document(
        self, mock_datetime, mock_uuid, mock_unlink, mock_get_conn, mock_get_creds,
        mock_embed, mock_chunk, mock_loader, mock_tempfile
    ):
        """Test processing a document."""
        # Mock datetime
        mock_now = MagicMock()
        mock_datetime.now.return_value = mock_now
        
        # Mock the temporary file
        mock_temp_file = MagicMock()
        mock_temp_file.name = "/tmp/test_file"
        mock_tempfile.NamedTemporaryFile.return_value.__enter__.return_value = mock_temp_file
        
        # Mock UUID
        mock_uuid.side_effect = ["chunk-1", "chunk-2"]
        
        # Mock document loader
        mock_doc_loader = MagicMock()
        mock_loader.return_value = mock_doc_loader
        
        # Create mock documents
        class MockDocument:
            def __init__(self, page_content, metadata):
                self.page_content = page_content
                self.metadata = metadata
        
        mock_documents = [
            MockDocument("Content 1", {"page": 1}),
            MockDocument("Content 2", {"page": 2})
        ]
        mock_doc_loader.load.return_value = mock_documents
        
        # Mock chunking
        mock_chunks = [
            MockDocument("Chunk 1", {"page": 1}),
            MockDocument("Chunk 2", {"page": 2})
        ]
        mock_chunk.return_value = mock_chunks
        
        # Mock embedding
        mock_embed.side_effect = [
            [0.1, 0.2, 0.3],
            [0.4, 0.5, 0.6]
        ]
        
        # Mock PostgreSQL connection
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn
        
        # Mock credentials
        mock_get_creds.return_value = {"host": "test-host"}
        
        # Test parameters
        container_name = "test-container"
        blob_path = "uploads/user-1/doc-1/test.pdf"
        document_id = "doc-1"
        user_id = "user-1"
        mime_type = "application/pdf"
        
        # Call the function
        num_chunks, chunk_ids = process_document(container_name, blob_path, document_id, user_id, mime_type)
        
        # Verify results
        self.assertEqual(num_chunks, 2)
        self.assertEqual(chunk_ids, ["chunk-1", "chunk-2"])
        
        # Verify blob download
        self.mock_blob_client.download_blob_to_file.assert_called_once()
        
        # Verify temporary file cleanup
        mock_unlink.assert_called_once_with("/tmp/test_file")
        
        # Verify document insertion
        mock_cursor.execute.assert_any_call(
            """
        INSERT INTO documents (document_id, user_id, file_name, mime_type, status, bucket, key, created_at, updated_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        RETURNING id
        """,
            unittest.mock.ANY  # We don't need to check the exact values here
        )
        
        # Verify chunk insertions
        self.assertEqual(mock_cursor.execute.call_count, 3)  # 1 for document + 2 for chunks

    @patch("document_processor.document_processor.func")
    def test_main_healthcheck(self, mock_func):
        """Test the Azure Function for a health check."""
        # Create a health check request
        mock_req = MagicMock()
        mock_req.get_json.return_value = {"action": "healthcheck"}
        
        # Mock HTTP response
        mock_http_response = MagicMock()
        mock_func.HttpResponse.return_value = mock_http_response
        
        # Call the function
        response = process_document(mock_req)
        
        # Verify results
        self.assertEqual(response, mock_http_response)
        mock_func.HttpResponse.assert_called_once()
        # Check that the response contains the expected data
        call_args = mock_func.HttpResponse.call_args
        response_body = json.loads(call_args[0][0])
        self.assertEqual(response_body["message"], "Document processor is healthy")
        self.assertEqual(response_body["stage"], "test")

    @patch("document_processor.document_processor.func")
    @patch("document_processor.document_processor.process_document")
    def test_main_event_request(self, mock_process, mock_func):
        """Test the Azure Function for a document processing request."""
        # Mock the process_document function
        mock_process.return_value = (2, ["chunk-1", "chunk-2"])
        
        # Create a document event request
        mock_req = MagicMock()
        mock_req.get_json.return_value = {
            "container": "test-container",
            "blob_path": "uploads/user-1/doc-1/test.pdf",
            "document_id": "doc-1",
            "user_id": "user-1",
            "mime_type": "application/pdf"
        }
        
        # Mock HTTP response
        mock_http_response = MagicMock()
        mock_func.HttpResponse.return_value = mock_http_response
        
        # Call the function
        response = process_document(mock_req)
        
        # Verify results
        self.assertEqual(response, mock_http_response)
        mock_func.HttpResponse.assert_called_once()
        # Check that the response contains the expected data
        call_args = mock_func.HttpResponse.call_args
        response_body = json.loads(call_args[0][0])
        self.assertEqual(response_body["message"], "Successfully processed document: doc-1")
        self.assertEqual(response_body["document_id"], "doc-1")
        self.assertEqual(response_body["num_chunks"], 2)
        
        # Verify process_document call
        mock_process.assert_called_once_with(
            "test-container", "uploads/user-1/doc-1/test.pdf", "doc-1", "user-1", "application/pdf"
        )

    @patch("document_processor.document_processor.func")
    @patch("document_processor.document_processor.process_document")
    def test_main_error_handling(self, mock_process, mock_func):
        """Test the Azure Function error handling."""
        # Mock process_document to raise an exception
        mock_process.side_effect = Exception("Error processing document")
        
        # Create a document event request
        mock_req = MagicMock()
        mock_req.get_json.return_value = {
            "container": "test-container",
            "blob_path": "uploads/user-1/doc-1/test.pdf",
            "document_id": "doc-1",
            "user_id": "user-1",
            "mime_type": "application/pdf"
        }
        
        # Mock HTTP response
        mock_http_response = MagicMock()
        mock_func.HttpResponse.return_value = mock_http_response
        
        # Call the function
        response = process_document(mock_req)
        
        # Verify results
        self.assertEqual(response, mock_http_response)
        mock_func.HttpResponse.assert_called_once()
        # Check that the response contains the expected error message
        call_args = mock_func.HttpResponse.call_args
        response_body = json.loads(call_args[0][0])
        self.assertTrue("Error processing document" in response_body["message"])
        self.assertEqual(call_args[1]["status_code"], 500)


if __name__ == "__main__":
    unittest.main()