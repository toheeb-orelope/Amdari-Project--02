import os
import psycopg2
import psycopg2.extras

# def get_connection():
#     return psycopg2.connect(
#         os.environ.get("DATABASE_URL"),
#         cursor_factory=psycopg2.extras.RealDictCursor
#     )
# import os

# import psycopg2
# import psycopg2.extras


def get_connection():
    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL environment variable is required")

    connection_options = {
        "cursor_factory": psycopg2.extras.RealDictCursor,
        "connect_timeout": 5,
        "application_name": "sentinelpay-payments-api",
        "options": (
            "-c statement_timeout=10000 " "-c idle_in_transaction_session_timeout=10000"
        ),
    }

    if os.environ.get("ENVIRONMENT") == "production":
        connection_options["sslmode"] = os.environ.get(
            "DB_SSLMODE",
            "require",
        )

    return psycopg2.connect(database_url, **connection_options)
