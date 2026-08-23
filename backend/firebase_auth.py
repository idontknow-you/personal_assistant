"""Firebase Auth middleware — verifies ID tokens on protected routes."""

import functools
import firebase_admin
from firebase_admin import auth as fb_auth
from flask import request, g

_app_initialized = False


def init_firebase():
    """Initialize Firebase Admin SDK once. Call once at app startup."""
    global _app_initialized
    if _app_initialized:
        return
    creds_path = __import__("config").config.GOOGLE_APPLICATION_CREDENTIALS
    if creds_path:
        cred = firebase_admin.credentials.Certificate(creds_path)
        firebase_admin.initialize_app(cred)
    else:
        # Works on GCP/Render if GOOGLE_APPLICATION_CREDENTIALS is set in the
        # environment, or if the default service account is available.
        firebase_admin.initialize_app()
    _app_initialized = True


def verify_token(f):
    """Decorator: extract and verify the Firebase ID token from the
    Authorization header, then store the decoded claims in flask.g.user.

    Usage:
        @app.route("/api/protected")
        @verify_token
        def protected():
            uid = g.user["uid"]
            ...
    """

    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return {"error": "Missing or malformed Authorization header"}, 401

        id_token = header[len("Bearer "):]
        try:
            decoded = fb_auth.verify_id_token(id_token)
            g.user = decoded  # contains "uid", "email", etc.
        except fb_auth.InvalidIdTokenError:
            return {"error": "Invalid ID token"}, 401
        except fb_auth.ExpiredIdTokenError:
            return {"error": "Expired ID token"}, 401
        except Exception as e:
            return {"error": f"Token verification failed: {e}"}, 401

        return f(*args, **kwargs)

    return wrapper
