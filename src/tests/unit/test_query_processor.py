import os
import json
import unittest
from unittest.mock import patch, MagicMock
from decimal import Decimal
from azure.functions import HttpRequest

# Set environment variables for test
os.environ["COSMOS_SECRET_URI"] = "https://test-kv.vault.azure.net|cosmos-secret"
os.environ["GEMINI_SECRET_URI"] = "https://test-kv.vault.azure.net|gemini-api-key"
os.environ["GEMINI_MODEL"] = "models/gemini-pro"
os.environ["GEMINI_EMBEDDING_MODEL"] = "embedding-model"
os.environ["TEMPERATURE"] = "0.2"
os.environ["MAX_OUTPUT_TOKENS"] = "1024"
os.environ["TOP_K"] = "5"
os.environ["TOP_P"] = "0.8"
os.environ["STAGE"] = "test"

from query_processor.function_app import (
    get_secret, embed_query, fetch_top_chunks,
    generate_response, query_handler
)

class TestQueryProcessor(unittest.TestCase):

    def setUp(self):
        self.secret_patcher = patch("query_processor.SecretClient")
        self.cred_patcher = patch("query_processor.DefaultAzureCredential")
        self.cosmos_patcher = patch("query_processor.CosmosClient")
        self.genai_patcher = patch("query_processor.client")

        self.mock_secret = self.secret_patcher.start()
        self.mock_cred = self.cred_patcher.start()
        self.mock_cosmos = self.cosmos_patcher.start()
        self.mock_genai = self.genai_patcher.start()

    def tearDown(self):
        self.secret_patcher.stop()
        self.cred_patcher.stop()
        self.cosmos_patcher.stop()
        self.genai_patcher.stop()

    def test_get_secret(self):
        mock_client = MagicMock()
        mock_client.get_secret.return_value.value = "test-value"
        self.mock_secret.return_value = mock_client
        value = get_secret("https://test-kv.vault.azure.net|secret-name")
        self.assertEqual(value, "test-value")

    def test_embed_query(self):
        mock_response = MagicMock()
        mock_response.embeddings = [MagicMock()]
        mock_response.embeddings[0].values = [0.1, 0.2, 0.3]
        self.mock_genai.embed_content.return_value = mock_response

        embedding = embed_query("test query")
        self.assertEqual(embedding, [0.1, 0.2, 0.3])
        self.mock_genai.embed_content.assert_called_once()

    def test_generate_response(self):
        mock_response = MagicMock()
        mock_response.text = "This is the response."
        self.mock_genai.generate_content.return_value = mock_response

        chunks = [{"file_name": "doc.pdf", "content": "AI content"}]
        answer = generate_response("What is AI?", chunks)
        self.assertIn("This is the response.", answer)

    @patch("query_processor.embed_query")
    @patch("query_processor.fetch_top_chunks")
    @patch("query_processor.generate_response")
    def test_query_handler_success(self, mock_generate, mock_fetch, mock_embed):
        mock_embed.return_value = [0.1] * 768
        mock_fetch.return_value = [{"chunk_id": "c1", "content": "test", "file_name": "doc.pdf"}]
        mock_generate.return_value = "final answer"

        req = MagicMock()
        req.get_json.return_value = {"user_id": "u123", "query": "What is RAG?"}
        response = query_handler(req)

        self.assertEqual(response.status_code, 200)
        body = json.loads(response.get_body())
        self.assertEqual(body["answer"], "final answer")
        self.assertEqual(body["context_used"], ["c1"])

    def test_query_handler_missing_query(self):
        req = MagicMock()
        req.get_json.return_value = {"user_id": "u123"}
        response = query_handler(req)
        self.assertEqual(response.status_code, 400)
        body = json.loads(response.get_body())
        self.assertIn("Query is required", json.dumps(body))

if __name__ == "__main__":
    unittest.main()
