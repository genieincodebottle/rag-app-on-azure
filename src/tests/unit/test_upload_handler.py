"""Test cases for the upload_handler Azure Function."""
import json
import os
import unittest
from unittest.mock import MagicMock, patch
from datetime import datetime

"""Set up test environment."""
# Set environment variables
os.environ["DOCUMENTS_CONTAINER"] = "test-container"
os.environ["DOCUMENTS_STORAGE"] = "teststorage"
os.environ["METADATA_COSMOS_ACCOUNT"] = "test-cosmos"
os.environ["METADATA_COSMOS_DATABASE"] = "test-db"
os.environ["METADATA_CONTAINER"] = "test-container"
os.environ["STAGE"] = "test"
os.environ["DB_SECRET_URI"] = "https://test-kv.vault.azure.net/secrets/db-credentials"

# Now import the module under test - mocks are already in place globally from conftest
from upload_handler.upload_handler import (
    main, get_postgres_credentials, get_postgres_connection, get_mime_type
)

class TestUploadHandler(unittest.TestCase):
    """Test cases for the upload_handler Azure Function."""

    def setUp(self):
        # Mock Azure clients
        self.blob_patcher = patch("upload_handler.upload_handler.BlobServiceClient")
        self.cosmos_patcher = patch("upload_handler.upload_handler.CosmosClient")
        self.secret_patcher = patch("upload_handler.upload_handler.SecretClient")
        self.credential_patcher = patch("upload_handler.upload_handler.DefaultAzureCredential")
        
        self.mock_blob = self.blob_patcher.start()
        self.mock_cosmos = self.cosmos_patcher.start()
        self.mock_secret = self.secret_patcher.start()
        self.mock_credential = self.credential_patcher.start()
        
        # Set up mock blob client
        self.mock_blob_service_client = MagicMock()
        self.mock_container_client = MagicMock()
        self.mock_blob_client = MagicMock()
        self.mock_container_client.get_blob_client.return_value = self.mock_blob_client
        self.mock_blob_service_client.get_container_client.return_value = self.mock_container_client
        self.mock_blob.return_value = self.mock_blob_service_client
        
        # Set up mock cosmos client
        self.mock_cosmos_client = MagicMock()
        self.mock_database_client = MagicMock()
        self.mock_container_client_cosmos = MagicMock()
        self.mock_database_client.get_container_client.return_value = self.mock_container_client_cosmos
        self.mock_cosmos_client.get_database_client.return_value = self.mock_database_client
        self.mock_cosmos.return_value = self.mock_cosmos_client

    def tearDown(self):
        """Clean up test environment."""
        # Clean up environment variables
        for key in [
            "DOCUMENTS_CONTAINER", "DOCUMENTS_STORAGE", "METADATA_COSMOS_ACCOUNT",
            "METADATA_COSMOS_DATABASE", "METADATA_CONTAINER", "STAGE", "DB_SECRET_URI"
        ]:
            if key in os.environ:
                del os.environ[key]
                
        # Stop patchers
        self.blob_patcher.stop()
        self.cosmos_patcher.stop()
        self.secret_patcher.stop()
        self.credential_patcher.stop()

    @patch("upload_handler.upload_handler.SecretClient")
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

    @patch("upload_handler.upload_handler.psycopg2")
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

    def test_get_mime_type(self):
        """Test determining MIME type from file extension."""
        # Test various file extensions
        test_cases = [
            ("document.pdf", "application/pdf"),
            ("file.txt", "text/plain"),
            ("data.csv", "text/csv"),
            ("document.doc", "application/msword"),
            ("document.docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
            ("spreadsheet.xls", "application/vnd.ms-excel"),
            ("spreadsheet.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
            ("data.json", "application/json"),
            ("readme.md", "text/markdown"),
            ("unknown.xyz", "application/octet-stream")
        ]

        for file_name, expected_mime_type in test_cases:
            mime_type = get_mime_type(file_name)
            self.assertEqual(mime_type, expected_mime_type)

    @patch("upload_handler.upload_handler.func")
    def test_main_healthcheck(self, mock_func):
        """Test the Azure Function for a health check."""
        # Create a health check request
        mock_req = MagicMock()
        mock_req.get_json.return_value = {"action": "healthcheck"}
        
        # Mock HTTP response
        mock_http_response = MagicMock()
        mock_func.HttpResponse.return_value = mock_http_response
        
        # Call the function
        response = main(mock_req)
        
        # Verify results
        self.assertEqual(response, mock_http_response)
        mock_func.HttpResponse.assert_called_once()
        # Check that the response contains the expected data
        call_args = mock_func.HttpResponse.call_args
        response_body = json.loads(call_args[0][0])
        self.assertEqual(response_body["message"], "Upload handler is healthy")
        self.assertEqual(response_body["stage"], "test")

    @patch("upload_handler.upload_handler.func")
    def test_main_missing_file_data(self, mock_func):
        """Test the Azure Function when file data is missing."""
        # Create a request with missing file content
        mock_req = MagicMock()
        mock_req.get_json.return_value = {"file_name": "test.pdf"}
        
        # Mock HTTP response
        mock_http_response = MagicMock()
        mock_func.HttpResponse.return_value = mock_http_response
        
        # Call the function
        response = main(mock_req)
        
        # Verify results
        self.assertEqual(response, mock_http_response)
        mock_func.HttpResponse.assert_called_once()
        # Check that the response contains the expected error message
        call_args = mock_func.HttpResponse.call_args
        response_body = json.loads(call_args[0][0])
        self.assertEqual(response_body["message"], "File content and name are required")
        self.assertEqual(call_args[1]["status_code"], 400)

    @patch("upload_handler.upload_handler.func")
    @patch("upload_handler.upload_handler.base64")
    @patch("upload_handler.upload_handler.uuid")
    @patch("upload_handler.upload_handler.datetime")
    @patch("upload_handler.upload_handler.get_postgres_credentials")
    @patch("upload_handler.upload_handler.get_postgres_connection")
    def test_main_success(self, mock_get_conn, mock_get_creds, mock_datetime, 
                          mock_uuid, mock_base64, mock_func):
        """Test the Azure Function for successful file upload."""
        # Mock base64 decode
        mock_base64.b64decode.return_value = b"file content"
        
        # Mock UUID
        mock_uuid.uuid4.return_value = "test-doc-id"
        
        # Mock datetime
        mock_now = datetime.now()
        mock_datetime.now.return_value = mock_now
        
        # Mock PostgreSQL connection
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_conn.cursor.return_value = mock_cursor
        mock_get_conn.return_value = mock_conn
        
        # Mock credentials
        mock_get_creds.return_value = {"host": "test-host"}
        
        # Create a request with file data
        mock_req = MagicMock()
        mock_req.get_json.return_value = {
            "file_content": "ZmlsZSBjb250ZW50",  # base64 "file content"
            "file_name": "test.pdf",
            "user_id": "test-user"
        }
        
        # Mock HTTP response
        mock_http_response = MagicMock()
        mock_func.HttpResponse.return_value = mock_http_response
        
        # Call the function
        response = main(mock_req)
        
        # Verify results
        self.assertEqual(response, mock_http_response)
        mock_func.HttpResponse.assert_called_once()
        # Check that the response contains the expected data
        call_args = mock_func.HttpResponse.call_args
        response_body = json.loads(call_args[0][0])
        self.assertEqual(response_body["message"], "File uploaded successfully")
        self.assertEqual(response_body["document_id"], "test-doc-id")
        self.assertEqual(response_body["file_name"], "test.pdf")
        
        # Verify blob upload
        self.mock_blob_client.upload_blob.assert_called_once()
        
        # Verify PostgreSQL insertion
        mock_cursor.execute.assert_called_once()
        
        # Verify Cosmos DB item creation
        self.mock_container_client_cosmos.create_item.assert_called_once()


if __name__ == "__main__":
    unittest.main()