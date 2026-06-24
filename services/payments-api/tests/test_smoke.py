"""Smoke tests for payments-api startup and security boundaries."""

import os
import secrets
import unittest

os.environ["ENVIRONMENT"] = "testing"
os.environ["JWT_SECRET"] = secrets.token_urlsafe(48)
os.environ["SECRET_KEY"] = secrets.token_urlsafe(48)
os.environ["RATELIMIT_STORAGE_URI"] = "memory://"

from app.main import create_app


class PaymentsApiSmokeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app = create_app()
        app.config["TESTING"] = True
        cls.client = app.test_client()

    def test_health(self):
        response = self.client.get("/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["status"], "ok")

    def test_protected_route_requires_authentication(self):
        response = self.client.get("/v1/accounts/")

        self.assertEqual(response.status_code, 401)
        self.assertEqual(
            response.get_json()["error"],
            "missing or malformed Authorization header",
        )

    def test_registration_rejects_non_object_json(self):
        response = self.client.post("/v1/auth/register", json=[])

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.get_json()["error"],
            "request body must be a JSON object",
        )

    def test_unknown_route_does_not_expose_debug_details(self):
        response = self.client.get("/route-that-does-not-exist")
        body = response.get_json()

        self.assertEqual(response.status_code, 404)
        self.assertEqual(set(body), {"error"})
        self.assertNotIn("trace", body)
        self.assertNotIn("type", body)


if __name__ == "__main__":
    unittest.main()
