"""Thin wrapper around the Google Generative AI SDK for Gemini."""

import google.generativeai as genai
from config import config

genai.configure(api_key=config.GEMINI_API_KEY)


def _build_chat_model():
    return genai.GenerativeModel(
        model_name=config.GEMINI_MODEL,
        system_instruction=_SYSTEM_PROMPT,
    )


_SYSTEM_PROMPT = """\
You are Personal OS, a calm, concise personal assistant living inside a \
productivity app. You help with:
- Task planning, prioritization, and breaking work into steps
- Habit and streak advice
- Reflecting on diary entries and mood patterns
- DSA problem-solving strategies and spaced repetition guidance
- Brain dump sorting — categorizing raw thoughts into actionable items

Personality:
- Be direct and brief. No fluff, no "Great question!" preamble.
- When sorting a brain dump, reply ONLY with valid JSON (see below).
- Otherwise reply in plain conversational text.
- Reference the user's data when relevant (streaks, recent moods, etc.)
- If the user asks something outside your scope, say so honestly.

Brain dump auto-sort format — when the user asks you to sort/categorize \
brain dump entries, reply with ONLY a JSON array (no markdown fences, no \
explanation before or after). Each element:
{
  "text": "the original text",
  "category": "task" | "note" | "diary" | "dsa" | "people" | "braindump",
  "title": "short summary title (<= 60 chars)"
}
"""


def generate(prompt: str) -> str:
    """Send a single prompt and return the raw text response."""
    model = _build_chat_model()
    response = model.generate_content(prompt)
    return response.text


def chat(message: str, history: list[dict] | None = None) -> str:
    """Send a chat message and return the assistant's reply.

    Args:
        message: The user's latest message.
        history: Optional list of {"role": "user"|"model", "parts": [...]}.

    Returns:
        The assistant's text response.
    """
    model = _build_chat_model()
    chat_session = model.start_chat(history=history or [])
    response = chat_session.send_message(message)
    return response.text


def auto_sort(texts: list[str]) -> list[dict]:
    """Send raw brain dump entries to Gemini for categorization.

    Args:
        texts: List of raw text strings to sort.

    Returns:
        List of dicts with keys: text, category, title.
    """
    model = _build_chat_model()
    joined = "\n".join(f"- {t}" for t in texts)
    prompt = (
        "Sort these brain dump entries into categories. "
        "Reply with ONLY a JSON array, no markdown fences:\n\n"
        f"{joined}"
    )
    response = model.generate_content(prompt)
    raw = response.text.strip()
    # Strip markdown fences if Gemini wraps them anyway
    if raw.startswith("```"):
        raw = raw.split("\n", 1)[1]
        if raw.endswith("```"):
            raw = raw[: -len("```")]
        raw = raw.strip()
    import json
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return [
            {"text": t, "category": "braindump", "title": t[:60]}
            for t in texts
        ]
