"""Smoke tests for KYC API startup and security boundaries."""

import os
import unittest

os.environ["ENVIRONMENT"] = "testing"
os.environ["JWT_SECRET"] = "test-jwt-secret-with-at-least-32-bytes"
os.environ["RATELIMIT_STORAGE_URI"] = "memory://"

from app.main import create_app


class KycApiSmokeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app = create_app()
        app.config["TESTING"] = True
        cls.client = app.test_client()

    def test_health(self):
        response = self.client.get("/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["status"], "ok")

    def test_document_route_requires_authentication(self):
        response = self.client.get("/v1/documents/users/1/example.pdf")

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.get_json()["error"], "unauthorized")

    def test_verify_route_requires_authentication(self):
        response = self.client.post("/v1/verify/bvn", json={"bvn": "12345678901"})

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.get_json()["error"], "unauthorized")

    def test_unknown_route_does_not_expose_debug_details(self):
        response = self.client.get("/route-that-does-not-exist")
        body = response.get_json()

        self.assertEqual(response.status_code, 404)
        self.assertEqual(set(body), {"error"})
        self.assertNotIn("trace", body)
        self.assertNotIn("type", body)


if __name__ == "__main__":
    unittest.main()
