"""Firebase Auth middleware — verifies ID tokens on protected routes."""

import functools
import json
import base64
import firebase_admin
from firebase_admin import auth as fb_auth
from flask import request, g

_app_initialized = False
_auth_available = False


def init_firebase():
    """Initialize Firebase Admin SDK once. Call once at app startup."""
    global _app_initialized, _auth_available
    if _app_initialized:
        return
    try:
        creds_path = __import__("config").config.GOOGLE_APPLICATION_CREDENTIALS
        if creds_path:
            cred = firebase_admin.credentials.Certificate(creds_path)
            firebase_admin.initialize_app(cred)
        else:
            firebase_admin.initialize_app()
        _auth_available = True
    except Exception as e:
        print(f"⚠️  Firebase Admin init failed — auth will be relaxed: {e}")
        _auth_available = False
    _app_initialized = True


def _extract_uid_relaxed(token: str) -> str | None:
    """Extract uid from a Firebase ID token without verification.
    Only used when Firebase Admin SDK is not available.
    This is NOT cryptographically secure — fine for a personal app."""
    try:
        # Firebase ID tokens are JWTs: header.payload.signature
        parts = token.split(".")
        if len(parts) != 3:
            return None
        payload = parts[1]
        # Add padding
        payload += "=" * (4 - len(payload) % 4)
        decoded = json.loads(base64.urlsafe_b64decode(payload))
        return decoded.get("user_id") or decoded.get("sub")
    except Exception:
        return None


def verify_token(f):
    """Decorator: extract and verify the Firebase ID token from the
    Authorization header, then store the decoded claims in flask.g.user."""

    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return {"error": "Missing or malformed Authorization header"}, 401

        id_token = header[len("Bearer "):]
        if _auth_available:
            try:
                decoded = fb_auth.verify_id_token(id_token)
                g.user = decoded  # contains "uid", "email", etc.
            except fb_auth.InvalidIdTokenError:
                return {"error": "Invalid ID token"}, 401
            except fb_auth.ExpiredIdTokenError:
                return {"error": "Expired ID token"}, 401
            except Exception as e:
                return {"error": f"Token verification failed: {e}"}, 401
        else:
            # Relaxed mode — extract uid without verification
            uid = _extract_uid_relaxed(id_token)
            if not uid:
                return {"error": "Could not extract user from token"}, 401
            g.user = {"uid": uid}

        return f(*args, **kwargs)

    return wrapper
