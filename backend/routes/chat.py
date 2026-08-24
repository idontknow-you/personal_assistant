"""Chat endpoint — sends messages to Gemini, handles function calling."""

from flask import Blueprint, request, g
from firebase_auth import verify_token
from rate_limit import limiter
import gemini_client

chat_bp = Blueprint("chat", __name__, url_prefix="/api")


@chat_bp.route("/chat", methods=["POST"])
@limiter.limit("10 per minute")
@verify_token
def chat():
    """POST /api/chat

    Body:
        {"message": "...", "history": [{...}], "functionCalls": [...], "functionResults": [...]}

    Round 1 (no functionCalls/functionResults):
        Gemini decides whether to call a function or reply with text.

    Round 2 (with functionCalls + functionResults):
        Client executed the functions, sends results back.
        Gemini generates the natural language response.
    """
    uid = g.user["uid"]
    data = request.get_json(silent=True) or {}
    message = data.get("message", "").strip()
    history = data.get("history", [])
    function_calls = data.get("functionCalls")
    function_results = data.get("functionResults")

    if not message and not function_results:
        return {"error": "message is required"}, 400

    # Sanitize history — only accept valid role/parts structure
    clean_history = []
    for entry in history:
        role = entry.get("role")
        parts = entry.get("parts", [])
        if role in ("user", "model") and isinstance(parts, list) and parts:
            clean_history.append({"role": role, "parts": parts})

    try:
        if function_results:
            # Round 2: pass function calls + results back to Gemini
            result = gemini_client.continue_chat(
                message=message or "Please summarize the results for the user.",
                history=clean_history,
                function_calls=function_calls,
                function_results=function_results,
            )
            return result
        else:
            # Round 1: send message, check for function calls
            result = gemini_client.chat(message, history=clean_history)
            return result
    except Exception as e:
        return {"error": f"Gemini error: {e}"}, 502
