import os
import json
import unittest
from unittest.mock import MagicMock, patch
from azure.functions import HttpRequest

# Set up required env vars
os.environ["COSMOS_SECRET_URI"] = "https://test-kv.vault.azure.net|cosmos-secret"
os.environ["BLOB_SECRET_URI"] = "https://test-kv.vault.azure.net|blob-secret"
os.environ["BLOB_CONTAINER"] = "documents"
os.environ["GEMINI_SECRET_URI"] = "https://test-kv.vault.azure.net|gemini-secret"
os.environ["GEMINI_EMBEDDING_MODEL"] = "test-model"
os.environ["STAGE"] = "test"

from document_processor import function_app


class TestDocumentProcessorAzure(unittest.TestCase):

    def setUp(self):
        patcher_cred = patch("document_processor.function_app.DefaultAzureCredential")
        patcher_kv = patch("document_processor.function_app.SecretClient")
        patcher_blob = patch("document_processor.function_app.BlobServiceClient")
        patcher_cosmos = patch("document_processor.function_app.CosmosClient")
        patcher_gemini = patch("document_processor.function_app.client")
        patcher_pdf = patch("document_processor.function_app.PdfReader")

        self.mock_cred = patcher_cred.start()
        self.mock_kv = patcher_kv.start()
        self.mock_blob = patcher_blob.start()
        self.mock_cosmos = patcher_cosmos.start()
        self.mock_gemini = patcher_gemini.start()
        self.mock_pdf = patcher_pdf.start()

        self.addCleanup(patcher_cred.stop)
        self.addCleanup(patcher_kv.stop)
        self.addCleanup(patcher_blob.stop)
        self.addCleanup(patcher_cosmos.stop)
        self.addCleanup(patcher_gemini.stop)
        self.addCleanup(patcher_pdf.stop)

    def test_health_check(self):
        mock_req = MagicMock(spec=HttpRequest)
        mock_req.get_json.return_value = {"action": "healthcheck"}
        res = function_app.process_document(mock_req)
        self.assertEqual(res.status_code, 200)
        body = json.loads(res.get_body())
        self.assertEqual(body["message"], "Document processor is healthy")
        self.assertEqual(body["stage"], "test")

    @patch("document_processor.function_app.download_blob")
    @patch("document_processor.function_app.extract_text_from_pdf")
    @patch("document_processor.function_app.chunk_text")
    @patch("document_processor.function_app.store_chunks")
    def test_process_document_success(self, mock_store, mock_chunk, mock_extract, mock_download):
        mock_req = MagicMock(spec=HttpRequest)
        mock_req.get_json.return_value = {
            "file_name": "uploads/user1/doc1/sample.pdf",
            "user_id": "user1",
            "document_id": "doc1"
        }
        mock_download.return_value = "/tmp/sample.pdf"
        mock_extract.return_value = "Sample text"
        mock_chunk.return_value = [MagicMock(page_content="chunk", metadata={})]
        mock_store.return_value = None

        res = function_app.process_document(mock_req)
        self.assertEqual(res.status_code, 200)
        body = json.loads(res.get_body())
        self.assertEqual(body["message"], "Document processed")
        self.assertEqual(body["chunks_stored"], 1)

    def test_process_document_failure(self):
        mock_req = MagicMock(spec=HttpRequest)
        mock_req.get_json.side_effect = Exception("Mock failure")
        res = function_app.process_document(mock_req)
        self.assertEqual(res.status_code, 500)
        self.assertIn("Error:", res.get_body().decode())


if __name__ == "__main__":
    unittest.main()
