"""Thin wrapper around the Google Generative AI SDK for Gemini — with function calling."""

import datetime
import json
import google.generativeai as genai
from config import config

_WEEKDAYS = {
    "monday": 0,
    "tuesday": 1,
    "wednesday": 2,
    "thursday": 3,
    "friday": 4,
    "saturday": 5,
    "sunday": 6,
}


def _resolve_relative_weekday(weekday_name: str, today: datetime.date) -> str | None:
    """Turn a bare weekday name (from a phrase like "by Monday") into a
    concrete ISO date — today itself if today already is that weekday,
    otherwise the next occurrence within the following 7 days. Doing this
    in Python rather than trusting the model's own date arithmetic avoids
    off-by-one weekday mistakes."""
    target = _WEEKDAYS.get((weekday_name or "").strip().lower())
    if target is None:
        return None
    delta = (target - today.weekday()) % 7
    return (today + datetime.timedelta(days=delta)).isoformat()

genai.configure(api_key=config.GEMINI_API_KEY, transport="rest")


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
                description="List the user's current tasks. Use when they ask what tasks they have, what's due, how many tasks, etc.",
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
            genai.protos.FunctionDeclaration(
                name="list_notes",
                description="List the user's recent notes and diary entries. Use when they ask about their notes, journal entries, or what they wrote recently.",
                parameters=genai.protos.Schema(
                    type=genai.protos.Type.OBJECT,
                    properties={
                        "limit": genai.protos.Schema(
                            type=genai.protos.Type.INTEGER,
                            description="Max notes to return (default 10)",
                        ),
                    },
                ),
            ),
            genai.protos.FunctionDeclaration(
                name="list_braindump",
                description="List the user's brain dump entries. Use when they ask about their brain dumps or quick notes.",
                parameters=genai.protos.Schema(
                    type=genai.protos.Type.OBJECT,
                    properties={
                        "limit": genai.protos.Schema(
                            type=genai.protos.Type.INTEGER,
                            description="Max entries to return (default 10)",
                        ),
                    },
                ),
            ),
            genai.protos.FunctionDeclaration(
                name="list_dsa_problems",
                description="List the user's DSA problems and their review status. Use when they ask about their DSA practice.",
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
- When the user asks what they have (tasks, habits, alarms, notes), call the \
list function to get the actual data, then summarize it.
- Parse natural language into the right parameters: \
  "tomorrow" → tomorrow's ISO date, "every day" → empty frequency array, \
  "Mon Wed Fri" → [1, 3, 5], "8:30 AM" → hour=8, minute=30, \
  "high priority" → priority="high".
- After a function executes successfully, confirm what was created briefly.
- When you receive function results (data about tasks, habits, etc.), \
  summarize them clearly for the user.
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
    function_calls: list[dict] | None = None,
    function_results: list[dict] | None = None,
) -> dict:
    """Continue a chat after function execution, passing results back to Gemini.

    The history must include the original user message. We reconstruct the
    full conversation: user message → model's function_call → function results.

    Returns:
        {"reply": str} with the natural language response after function execution.
    """
    model = _build_chat_model()

    # Build the full conversation history that includes the function call
    # and response, so Gemini knows which data belongs to which request.
    full_history = list(history or [])

    # Add the model's turn that made the function calls
    if function_calls:
        # Reconstruct the function call parts
        fc_parts = []
        for fc in function_calls:
            fc_parts.append(
                genai.protos.Part(
                    function_call=genai.protos.FunctionCall(
                        name=fc["name"],
                        args=fc.get("args", {}),
                    )
                )
            )
        full_history.append({"role": "model", "parts": fc_parts})

        # Add the function response parts
        if function_results:
            fr_parts = []
            for fr in function_results:
                fr_parts.append(
                    genai.protos.Part(
                        function_response=genai.protos.FunctionResponse(
                            name=fr["name"],
                            response=fr.get("result", {}),
                        )
                    )
                )
            full_history.append({"role": "function", "parts": fr_parts})

    chat_session = model.start_chat(history=full_history)

    # Send the user's original message as a follow-up, or a generic prompt
    response = chat_session.send_message(
        message or "Please summarize the results for the user."
    )

    result = {}
    for part in response.parts:
        if hasattr(part, "text") and part.text:
            result["reply"] = part.text

    if not result:
        result["reply"] = "Done!"

    return result


_AUTO_SORT_SYSTEM_PROMPT = """\
You sort raw "brain dump" entries from a productivity app into structured \
data the app can act on directly. For EACH entry, extract everything a \
human would naturally infer from it — dates, times, deadlines, and \
whether it's really several steps bundled into one dump.

Reply with ONLY a JSON array (no markdown fences, no commentary before or \
after). Each element must have exactly these keys:

{
  "text": "<the original entry text, unchanged>",
  "category": "task" | "note" | "diary" | "dsa" | "people" | "braindump",
  "title": "<short summary, <= 60 chars>",
  "dueDate": "<YYYY-MM-DD, or null>",
  "relativeWeekday": "<monday|tuesday|...|sunday, or null>",
  "alarmHour": <0-23 integer, or null>,
  "alarmMinute": <0-59 integer, or null>,
  "notes": "<extra detail beyond the title, or null>",
  "subtasks": ["<step 1>", "<step 2>", ...] or null
}

RULES:
- category "task": anything actionable with a verb — "do X", "call Y", \
  "interview on...", "finish the report by...". Give it a short, clean \
  title, e.g. "interview on aug 31 9pm" -> title "Interview".
- If an entry names a specific date ("aug 31", "31/8", "next friday"), put \
  it in "dueDate" as YYYY-MM-DD. Assume the current year unless that would \
  put the date in the past, in which case use next year.
- If an entry ONLY names a bare weekday with no explicit date ("by \
  Monday", "before Thursday"), put the weekday name in "relativeWeekday" \
  instead of guessing the date yourself — the app resolves the exact date \
  relative to today.
- If an entry names a clock time ("9pm", "at 9:30am"), split it into \
  "alarmHour" (24h) and "alarmMinute". An entry with both a date/weekday \
  AND a time should get both — the app creates a task with that deadline \
  plus a linked alarm at that time.
- If an entry is long, rambling, or clearly lists multiple distinct \
  action items toward one goal, use category "task", write one \
  overarching title, and break the individual items into "subtasks" (one \
  short string per step). Put any leftover context that isn't itself a \
  step into "notes".
- If an entry is a long thought, story, or reflection with no discrete \
  action items, use category "note" or "diary" and put the FULL original \
  text in "notes" (not just a short fragment) so nothing is lost.
- Use "people" for entries primarily about a specific person, "dsa" for \
  coding/DSA problems, and "braindump" only when nothing else fits.
- Never invent a date, time, or subtask that isn't implied by the text — \
  leave the field null instead of guessing.
"""


def _build_auto_sort_model():
    # Deliberately a separate model instance from the chat one, with no
    # function-calling tools attached — tool defs on the chat model can
    # tempt Gemini into emitting a function call instead of the plain JSON
    # array this endpoint needs.
    return genai.GenerativeModel(
        model_name=config.GEMINI_MODEL,
        system_instruction=_AUTO_SORT_SYSTEM_PROMPT,
    )


def auto_sort(texts: list[str]) -> list[dict]:
    """Send raw brain dump entries to Gemini for categorization, then
    resolve any bare-weekday reference ("by Monday") into a concrete date.
    """
    model = _build_auto_sort_model()
    today = datetime.date.today()
    joined = "\n".join(f"- {t}" for t in texts)
    prompt = (
        f"Today's date is {today.isoformat()} ({today.strftime('%A')}).\n\n"
        "Sort these brain dump entries:\n\n"
        f"{joined}"
    )
    response = model.generate_content(prompt)
    raw = response.text.strip()
    if raw.startswith("```"):
        raw = raw.split("\n", 1)[1]
        if raw.endswith("```"):
            raw = raw[: -len("```")]
        raw = raw.strip()

    try:
        results = json.loads(raw)
    except json.JSONDecodeError:
        return [
            {"text": t, "category": "braindump", "title": t[:60]}
            for t in texts
        ]

    if not isinstance(results, list):
        return [
            {"text": t, "category": "braindump", "title": t[:60]}
            for t in texts
        ]

    for r in results:
        if not isinstance(r, dict):
            continue
        if not r.get("dueDate") and r.get("relativeWeekday"):
            r["dueDate"] = _resolve_relative_weekday(r["relativeWeekday"], today)
        r.pop("relativeWeekday", None)

    return results