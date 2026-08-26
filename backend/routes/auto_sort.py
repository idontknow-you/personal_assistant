"""Auto-sort endpoint — categorizes raw brain dump entries via Gemini."""

from flask import Blueprint, current_app, request, g
from firebase_auth import verify_token
from rate_limit import limiter
import gemini_client

auto_sort_bp = Blueprint("auto_sort", __name__, url_prefix="/api")


@auto_sort_bp.route("/auto-sort", methods=["POST"])
@limiter.limit("10 per minute")
@verify_token
def auto_sort():
    """POST /api/auto-sort

    Body:
        {"entries": ["raw text 1", "raw text 2", ...]}

    Returns:
        {"results": [{"text": "...", "category": "task"|"note"|..., "title": "..."}]}
    """
    data = request.get_json(silent=True) or {}
    entries = data.get("entries", [])

    if not entries or not isinstance(entries, list):
        return {"error": "entries array is required"}, 400

    # Limit to 20 entries per request to stay within token limits
    entries = entries[:20]

    try:
        results = gemini_client.auto_sort(entries)
        return {"results": results}
    except Exception as e:
        # Log the real exception for us; never show raw error internals
        # to the user, who just sees a generic 502-triggered message.
        current_app.logger.exception("Auto-sort failed")
        return {
            "error": "Couldn't sort your brain dump right now — please try again in a moment."
        }, 502