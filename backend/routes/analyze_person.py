"""People analysis endpoint — analyzes entries about a person via Gemini."""

from flask import Blueprint, request, g
from firebase_auth import verify_token
from rate_limit import limiter
import gemini_client

analyze_person_bp = Blueprint("analyze_person", __name__, url_prefix="/api")

_ANALYSIS_PROMPT = """\
You are analyzing text entries someone wrote about a person in their life. \
Provide analysis in these THREE sections, separated by the section headers below.

Write in second person ("you"). Be honest and direct — the user wants real \
insights, not sugar-coating.

## Patterns
What behavioral patterns do you notice? Recurring themes in how this person \
acts, what they say, how they treat the user? Be specific — quote or \
paraphrase the entries.

## Red Flags
Any concerning behaviors, manipulation tactics, inconsistency, or warning \
signs? If there are none, say so clearly — don't invent red flags.

## Emotional Reflection
How is this person likely making the user feel? What emotions come through \
in the user's writing about them? What might the user be suppressing or not \
seeing?

## Communication Style
How does this person communicate? What's their style — direct, passive, \
aggressive, passive-aggressive? Any patterns in how they talk to the user?

---

Entries to analyze:
"""


@analyze_person_bp.route("/analyze-person", methods=["POST"])
@limiter.limit("10 per minute")
@verify_token
def analyze_person():
    """POST /api/analyze-person

    Body:
        {"entries": [{"text": "...", "sourceType": "diary"|"chat"|...}]}

    Returns:
        {
            "patterns": "...",
            "redFlags": "...",
            "emotionalReflection": "...",
            "communicationStyle": "..."
        }
    """
    data = request.get_json(silent=True) or {}
    entries = data.get("entries", [])

    if not entries or not isinstance(entries, list):
        return {"error": "entries array is required"}, 400

    # Build the entries text for the prompt
    entry_texts = []
    for e in entries[:30]:  # cap at 30 entries to stay within token limits
        text = e.get("text", "")
        source = e.get("sourceType", "unknown")
        entry_texts.append(f"[{source}] {text}")

    full_prompt = _ANALYSIS_PROMPT + "\n".join(entry_texts)

    try:
        response = gemini_client.generate(full_prompt)
        # Parse the response into sections
        sections = _parse_sections(response)
        return sections
    except Exception as e:
        return {"error": f"Analysis failed: {e}"}, 502


def _parse_sections(text: str) -> dict:
    """Parse the Gemini response into the four analysis sections."""
    sections = {
        "patterns": "",
        "redFlags": "",
        "emotionalReflection": "",
        "communicationStyle": "",
    }

    current_key = None
    lines = []

    for line in text.split("\n"):
        lower = line.lower().strip()
        if "## patterns" in lower or lower == "patterns":
            current_key = "patterns"
            continue
        elif "## red flag" in lower or "red flag" in lower:
            current_key = "redFlags"
            continue
        elif "## emotional" in lower or "emotional reflection" in lower:
            current_key = "emotionalReflection"
            continue
        elif "## communication" in lower or "communication style" in lower:
            current_key = "communicationStyle"
            continue

        if current_key is not None:
            lines.append(line)
            # If we hit a new section or end, flush
            if any(
                marker in lower
                for marker in [
                    "## patterns",
                    "## red flag",
                    "## emotional",
                    "## communication",
                ]
            ):
                # This line starts a new section — it was already appended,
                # but we need to figure out which section it belongs to.
                # Reset and re-assign (simpler to just collect all and split later).
                pass

    # Simpler approach: split by ## headers
    import re
    parts = re.split(
        r"##\s*(Patterns|Red Flags?|Emotional Reflection|Communication Style)",
        text,
    )

    key_map = {
        "Patterns": "patterns",
        "Red Flags": "redFlags",
        "Red Flag": "redFlags",
        "Emotional Reflection": "emotionalReflection",
        "Communication Style": "communicationStyle",
    }

    i = 1  # skip text before first header
    while i < len(parts) - 1:
        header = parts[i].strip()
        body = parts[i + 1].strip()
        key = key_map.get(header)
        if key:
            sections[key] = body
        i += 2

    return sections
