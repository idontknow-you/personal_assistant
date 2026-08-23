"""Chat endpoint — sends messages to Gemini and returns responses."""

from flask import Blueprint, request, g
from firebase_auth import verify_token
import gemini_client

chat_bp = Blueprint("chat", __name__, url_prefix="/api")


@chat_bp.route("/chat", methods=["POST"])
@verify_token
def chat():
    """POST /api/chat

    Body:
        {"message": "...", "history": [{"role": "user"|"model", "parts": ["..."]}]}
    """
    uid = g.user["uid"]
    data = request.get_json(silent=True) or {}
    message = data.get("message", "").strip()
    history = data.get("history", [])

    if not message:
        return {"error": "message is required"}, 400

    # Sanitize history — only accept valid role/parts structure
    clean_history = []
    for entry in history:
        role = entry.get("role")
        parts = entry.get("parts", [])
        if role in ("user", "model") and isinstance(parts, list) and parts:
            clean_history.append({"role": role, "parts": parts})

    try:
        reply = gemini_client.chat(message, history=clean_history)
        return {"reply": reply}
    except Exception as e:
        return {"error": f"Gemini error: {e}"}, 502
