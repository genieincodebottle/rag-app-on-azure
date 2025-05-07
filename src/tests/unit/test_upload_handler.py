import unittest
import os
import json
import base64
from azure.functions import HttpRequest, HttpResponse
from datetime import datetime
from upload_handler.function_app import (
    get_secret,
    upload_to_blob_storage,
    store_metadata_to_cosmos,
    upload_handler
)

# Set env variables for function behavior
os.environ["STAGE"] = "test"
os.environ["BLOB_SECRET_URI"] = "https://mockvault.vault.azure.net|blob-secret"
os.environ["COSMOS_SECRET_URI"] = "https://mockvault.vault.azure.net|cosmos-secret"
os.environ["BLOB_CONTAINER"] = "test-container"

class TestUploadHandlerFunctions(unittest.TestCase):
    def make_http_request(self, body: dict) -> HttpRequest:
        return HttpRequest(
            method="POST",
            body=json.dumps(body).encode("utf-8"),
            url="/api/upload",
            headers={"Content-Type": "application/json"}
        )

    def test_get_secret(self):
        # Verifies mocked Key Vault return
        secret_value = get_secret("https://mockvault.vault.azure.net|blob-secret")
        self.assertEqual(secret_value, '{"GEMINI_API_KEY": "test-api-key"}')

    def test_upload_to_blob_storage(self):
        # Verifies blob upload and mock blob URL return
        file_url = upload_to_blob_storage("test.txt", b"dummy content")
        self.assertTrue(file_url.startswith("https://") or "test-container" in file_url)

    def test_store_metadata_to_cosmos(self):
        # Should run without exceptions with mocked Cosmos client
        metadata = {
            "id": "doc-123",
            "document_id": "doc-123",
            "user_id": "test-user",
            "file_name": "test.pdf",
            "mime_type": "application/pdf",
            "status": "uploaded",
            "bucket": "test-container",
            "key": "test.pdf",
            "url": "https://mock.blob/test.pdf",
            "created_at": datetime.utcnow().isoformat(),
            "updated_at": datetime.utcnow().isoformat()
        }
        store_metadata_to_cosmos(metadata)  # assert no exceptions raised

    def test_upload_handler_success(self):
        # Covers full flow: decode → upload → metadata → response
        encoded = base64.b64encode(b"file content").decode()
        req = self.make_http_request({
            "user_id": "abc",
            "file_name": "file.txt",
            "mime_type": "text/plain",
            "file_content": encoded
        })
        res: HttpResponse = upload_handler(req)
        self.assertEqual(res.status_code, 200)
        body = json.loads(res.get_body())
        self.assertIn("Upload successful", body["message"])
        self.assertTrue("document_id" in body)

    def test_upload_handler_invalid_json(self):
        # Simulate invalid JSON structure (e.g., not base64 or missing fields)
        req = self.make_http_request({"user_id": "abc"})
        res: HttpResponse = upload_handler(req)
        self.assertEqual(res.status_code, 500)
        self.assertIn("Error", res.get_body().decode())

    def test_upload_handler_invalid_base64(self):
        # Simulate invalid base64 content
        req = self.make_http_request({
            "user_id": "abc",
            "file_name": "test.txt",
            "mime_type": "text/plain",
            "file_content": "!!!!invalidbase64"
        })
        res: HttpResponse = upload_handler(req)
        self.assertEqual(res.status_code, 500)
        self.assertIn("Error", res.get_body().decode())

if __name__ == "__main__":
    unittest.main()
