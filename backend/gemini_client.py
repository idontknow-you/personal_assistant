"""Thin wrapper around the Google Generative AI SDK for Gemini — with function calling."""

import json
import google.generativeai as genai
from config import config

genai.configure(api_key=config.GEMINI_API_KEY)


# ---------------------------------------------------------------------------
# Tool definitions — what the assistant can do in the app
# ---------------------------------------------------------------------------

_TOOLS = [
    genai.protos.Tool(
        function_declarations=[
            genai.protos.FunctionDeclaration(
                name="create_task",
                description="Create a new task in the user's task list.",
                parameters=genai.protos.Schema(
                    type=genai.protos.Type.OBJECT,
                    properties={
                        "title": genai.protos.Schema(
                            type=genai.protos.Type.STRING,
                            description="Task title",
                        ),
                        "priority": genai.protos.Schema(
                            type=genai.protos.Type.STRING,
                            enum=["low", "medium", "high"],
                            description="Task priority (default: low)",
                        ),
                        "due_date": genai.protos.Schema(
                            type=genai.protos.Type.STRING,
                            description="Due date in ISO format (YYYY-MM-DD). Use today if not specified.",
                        ),
                        "notes": genai.protos.Schema(
                            type=genai.protos.Type.STRING,
                            description="Optional notes for the task",
                        ),
                        "repeat": genai.protos.Schema(
                            type=genai.protos.Type.STRING,
                            enum=["none", "daily", "weekly"],
                            description="Repeat type (default: none)",
                        ),
                    },
                    required=["title"],
                ),
            ),
            genai.protos.FunctionDeclaration(
                name="complete_task",
                description="Mark a task as complete or incomplete. Use this when the user says they finished a task.",
                parameters=genai.protos.Schema(
                    type=genai.protos.Type.OBJECT,
                    properties={
                        "task_id": genai.protos.Schema(
                            type=genai.protos.Type.STRING,
                            description="The Firestore document ID of the task",
                        ),
                        "completed": genai.protos.Schema(
                            type=genai.protos.Type.BOOLEAN,
                            description="true to mark complete, false to uncomplete",
                        ),
                    },
                    required=["task_id", "completed"],
                ),
            ),
            genai.protos.FunctionDeclaration(
                name="create_alarm",
                description="Create a new alarm. Use this when the user asks to set an alarm or reminder.",
                parameters=genai.protos.Schema(
                    type=genai.protos.Type.OBJECT,
                    properties={
                        "label": genai.protos.Schema(
                            type=genai.protos.Type.STRING,
                            description="Alarm label/name",
                        ),
                        "hour": genai.protos.Schema(
                            type=genai.protos.Type.INTEGER,
                            description="Hour in 24h format (0-23)",
                        ),
                        "minute": genai.protos.Schema(
                            type=genai.protos.Type.INTEGER,
                            description="Minute (0-59)",
                        ),
                        "repeat_days": genai.protos.Schema(
                            type=genai.protos.Type.ARRAY,
                            items=genai.protos.Schema(type=genai.protos.Type.INTEGER),
                            description="Days to repeat (1=Mon..7=Sun). Empty array for one-time.",
                        ),
                        "one_time_date": genai.protos.Schema(
                            type=genai.protos.Type.STRING,
                            description="For one-time alarms: date in ISO format (YYYY-MM-DD)",
                        ),
                    },
                    required=["label", "hour", "minute"],
                ),
            ),
            genai.protos.FunctionDeclaration(
                name="create_habit",
                description="Create a new habit the user wants to track.",
                parameters=genai.protos.Schema(
                    type=genai.protos.Type.OBJECT,
                    properties={
                        "name": genai.protos.Schema(
                            type=genai.protos.Type.STRING,
                            description="Habit name (e.g. 'Exercise', 'Read 30 mins')",
                        ),
                        "frequency": genai.protos.Schema(
                            type=genai.protos.Type.ARRAY,
                            items=genai.protos.Schema(type=genai.protos.Type.INTEGER),
                            description="Days to track (1=Mon..7=Sun). Empty for every day.",
                        ),
                    },
                    required=["name"],
                ),
            ),
            genai.protos.FunctionDeclaration(
                name="add_note",
                description="Add a note or diary entry. Use this when the user wants to write something down, journal, or save a thought.",
                parameters=genai.protos.Schema(
                    type=genai.protos.Type.OBJECT,
                    properties={
                        "title": genai.protos.Schema(
                            type=genai.protos.Type.STRING,
                            description="Note title",
                        ),
                        "content": genai.protos.Schema(
                            type=genai.protos.Type.STRING,
                            description="Note content/body",
                        ),
                    },
                    required=["title", "content"],
                ),
            ),
            genai.protos.FunctionDeclaration(
                name="add_braindump",
                description="Add a raw brain dump entry. Use this when the user wants to quickly jot something down without categorizing it.",
                parameters=genai.protos.Schema(
                    type=genai.protos.Type.OBJECT,
                    properties={
                        "text": genai.protos.Schema(
                            type=genai.protos.Type.STRING,
                            description="The raw text to save",
                        ),
                    },
                    required=["text"],
                ),
            ),
            genai.protos.FunctionDeclaration(
                name="add_dsa_problem",
                description="Add a DSA problem to track for spaced repetition review.",
                parameters=genai.protos.Schema(
                    type=genai.protos.Type.OBJECT,
                    properties={
                        "name": genai.protos.Schema(
                            type=genai.protos.Type.STRING,
                            description="Problem name (e.g. 'Two Sum', 'Merge Intervals')",
                        ),
                        "link": genai.protos.Schema(
                            type=genai.protos.Type.STRING,
                            description="Optional URL to the problem (LeetCode, etc.)",
                        ),
                    },
                    required=["name"],
                ),
            ),
            genai.protos.FunctionDeclaration(
                name="list_tasks",
                description="List the user's current tasks. Use when they ask what tasks they have, what's due, etc.",
                parameters=genai.protos.Schema(
                    type=genai.protos.Type.OBJECT,
                    properties={},
                ),
            ),
            genai.protos.FunctionDeclaration(
                name="list_habits",
                description="List the user's current habits and their streaks. Use when they ask about habits.",
                parameters=genai.protos.Schema(
                    type=genai.protos.Type.OBJECT,
                    properties={},
                ),
            ),
            genai.protos.FunctionDeclaration(
                name="list_alarms",
                description="List the user's current alarms. Use when they ask about alarms.",
                parameters=genai.protos.Schema(
                    type=genai.protos.Type.OBJECT,
                    properties={},
                ),
            ),
        ]
    )
]

# ---------------------------------------------------------------------------
# Model builder
# ---------------------------------------------------------------------------

def _build_chat_model():
    return genai.GenerativeModel(
        model_name=config.GEMINI_MODEL,
        system_instruction=_SYSTEM_PROMPT,
        tools=_TOOLS,
    )


_SYSTEM_PROMPT = """\
You are Personal OS, a calm, concise personal assistant living inside a \
productivity app. You help with tasks, alarms, habits, notes, brain dumps, \
DSA problems, and general productivity.

CRITICAL RULES:
- When the user asks you to CREATE, ADD, or SET something, you MUST call the \
appropriate function. Do NOT just say "Done!" without calling a function.
- When the user asks what they have (tasks, habits, alarms), call the list function.
- Parse natural language into the right parameters: \
  "tomorrow" → tomorrow's ISO date, "every day" → empty frequency array, \
  "Mon Wed Fri" → [1, 3, 5], "8:30 AM" → hour=8, minute=30, \
  "high priority" → priority="high".
- After a function executes successfully, confirm what was created briefly.
- Be direct and brief. No fluff, no "Great question!" preamble.
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


def chat(message: str, history: list[dict] | None = None) -> dict:
    """Send a chat message and return the assistant's response.

    Returns:
        {"reply": str} for a text response,
        {"functionCalls": [...]} if Gemini wants to call a function,
        {"reply": str, "functionCalls": [...]} if both text and calls.
    """
    model = _build_chat_model()
    chat_session = model.start_chat(history=history or [])
    response = chat_session.send_message(message)

    result = {}
    function_calls = []

    for part in response.parts:
        if hasattr(part, "function_call") and part.function_call:
            fc = part.function_call
            args = {}
            if fc.args:
                for key, value in fc.args.items():
                    # Convert proto values to Python primitives
                    if hasattr(value, "list_value"):
                        args[key] = list(value.list_value)
                    elif hasattr(value, "string_value"):
                        args[key] = value.string_value
                    elif hasattr(value, "number_value"):
                        num = value.number_value
                        args[key] = int(num) if num == int(num) else num
                    elif hasattr(value, "bool_value"):
                        args[key] = value.bool_value
                    else:
                        args[key] = str(value)
            function_calls.append({"name": fc.name, "args": args})
        elif hasattr(part, "text") and part.text:
            result["reply"] = part.text

    if function_calls:
        result["functionCalls"] = function_calls

    if not result:
        result["reply"] = "I'm not sure what to do with that. Could you rephrase?"

    return result


def continue_chat(
    message: str,
    history: list[dict] | None = None,
    function_results: list[dict] | None = None,
) -> dict:
    """Continue a chat after function execution, passing results back to Gemini.

    Returns:
        {"reply": str} with the natural language response after function execution.
    """
    model = _build_chat_model()
    chat_session = model.start_chat(history= history or [])

    # Build the function response message
    parts = []
    if function_results:
        for fr in function_results:
            # Create a Part with function response
            parts.append(
                genai.protos.Part(
                    function_response=genai.protos.FunctionResponse(
                        name=fr["name"],
                        response=fr.get("result", {}),
                    )
                )
            )
    else:
        parts.append(message)

    response = chat_session.send_message(parts)

    result = {}
    for part in response.parts:
        if hasattr(part, "text") and part.text:
            result["reply"] = part.text

    if not result:
        result["reply"] = "Done!"

    return result


def auto_sort(texts: list[str]) -> list[dict]:
    """Send raw brain dump entries to Gemini for categorization."""
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
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return [
            {"text": t, "category": "braindump", "title": t[:60]}
            for t in texts
        ]
