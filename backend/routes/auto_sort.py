"""Auto-sort endpoint — categorizes raw brain dump entries via Gemini."""

from flask import Blueprint, request, g
from firebase_auth import verify_token
import gemini_client

auto_sort_bp = Blueprint("auto_sort", __name__, url_prefix="/api")


@auto_sort_bp.route("/auto-sort", methods=["POST"])
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
        return {"error": f"Auto-sort failed: {e}"}, 502
