"""Semantic search endpoint — finds relevant notes, diary, and chat by meaning."""

from flask import Blueprint, request, g
from firebase_auth import verify_token
from rate_limit import limiter
import gemini_client

semantic_search_bp = Blueprint("semantic_search", __name__, url_prefix="/api")


@semantic_search_bp.route("/semantic-search", methods=["POST"])
@limiter.limit("10 per minute")
@verify_token
def semantic_search():
    """POST /api/semantic-search

    Body:
        {
            "query": "what did I write about feeling overwhelmed",
            "entries": [
                {"id": "1", "type": "note", "text": "...", "title": "...", "mood": "anxious"},
                {"id": "2", "type": "diary", "text": "...", "date": "..."},
                ...
            ]
        }

    Returns:
        {
            "results": [
                {"id": "1", "type": "note", "title": "...", "relevance": "high", "summary": "...", "date": "..."},
                ...
            ]
        }
    """
    data = request.get_json(silent=True) or {}
    query = data.get("query", "").strip()
    entries = data.get("entries", [])

    if not query:
        return {"error": "query is required"}, 400

    if not entries:
        return {"results": []}

    # Build entries text for Gemini
    entries_text = ""
    for i, e in enumerate(entries):
        etype = e.get("type", "unknown")
        title = e.get("title", "")
        text = e.get("text", "")[:200]  # truncate long entries
        mood = e.get("mood", "")
        date = e.get("date", "")
        meta = f"[{etype}]"
        if title:
            meta += f" {title}"
        if mood:
            meta += f" (mood: {mood})"
        if date:
            meta += f" {date}"
        entries_text += f"\n{i}: {meta} — {text}"

    prompt = f"""You are a semantic search engine for a personal productivity app.

The user searched for: "{query}"

Here are their entries (notes, diary, brain dumps, tasks):
{entries_text}

Find the entries most relevant to the search query. Rank by relevance.

Reply with ONLY a JSON array (no markdown fences). Each result:
{{
  "index": 0,
  "relevance": "high" | "medium" | "low",
  "summary": "1-2 sentence explanation of why this matches"
}}

Include ALL entries with "medium" or "high" relevance. Exclude "low" relevance.
If nothing is relevant, return an empty array [].
Max 8 results."""

    try:
        response = gemini_client.generate(prompt)
        raw = response.strip()
        # Strip markdown fences if present
        if raw.startswith("```"):
            raw = raw.split("\n", 1)[1]
            if raw.endswith("```"):
                raw = raw[:-3]
            raw = raw.strip()

        import json
        try:
            ranked = json.loads(raw)
        except json.JSONDecodeError:
            ranked = []

        # Map indices back to entry data
        results = []
        for r in ranked:
            idx = r.get("index", -1)
            if 0 <= idx < len(entries):
                e = entries[idx]
                results.append({
                    "id": e.get("id", ""),
                    "type": e.get("type", ""),
                    "title": e.get("title", ""),
                    "text": e.get("text", "")[:200],
                    "mood": e.get("mood", ""),
                    "date": e.get("date", ""),
                    "relevance": r.get("relevance", "medium"),
                    "summary": r.get("summary", ""),
                })

        return {"results": results}
    except Exception as e:
        return {"error": f"Search error: {e}"}, 502
