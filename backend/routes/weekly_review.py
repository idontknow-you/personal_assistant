"""Weekly review endpoint — Gemini summarizes the user's week."""

from flask import Blueprint, request, g
from firebase_auth import verify_token
import gemini_client

weekly_review_bp = Blueprint("weekly_review", __name__, url_prefix="/api")


@weekly_review_bp.route("/weekly-review", methods=["POST"])
@verify_token
def weekly_review():
    """POST /api/weekly-review

    Body:
        {
            "tasks": [{"title": "...", "completed": true, "dueDate": "..."}],
            "habits": [{"name": "...", "currentStreak": 5, "log": {...}}],
            "notes": [{"title": "...", "mood": "happy", "content": "..."}],
            "streak": 7,
            "period": "last 7 days"
        }
    """
    data = request.get_json(silent=True) or {}

    tasks = data.get("tasks", [])
    habits = data.get("habits", [])
    notes = data.get("notes", [])
    streak = data.get("streak", 0)

    # Build a concise data dump for Gemini
    task_summary = f"{len(tasks)} tasks total, {sum(1 for t in tasks if t.get('completed'))} completed"
    habit_lines = []
    for h in habits:
        name = h.get("name", "unknown")
        s = h.get("currentStreak", 0)
        habit_lines.append(f"  - {name}: streak {s} days")
    habit_summary = "\n".join(habit_lines) if habit_lines else "  No habits tracked"

    mood_counts = {}
    for n in notes:
        m = n.get("mood", "unknown")
        mood_counts[m] = mood_counts.get(m, 0) + 1
    mood_summary = ", ".join(f"{k}: {v}" for k, v in mood_counts.items()) if mood_counts else "No mood data"

    prompt = f"""You are a personal productivity coach. Write a brief weekly review for the user based on this data:

TASKS: {task_summary}
STREAK: {streak} days
HABITS:
{habit_summary}
MOODS THIS WEEK: {mood_summary}
NOTES WRITTEN: {len(notes)}

Write a concise, encouraging weekly review (4-6 sentences max):
1. Highlight what went well
2. Note any patterns (mood, consistency)
3. Suggest one concrete improvement for next week
4. End with a motivational note

Be direct and personal. Use "you" language. No fluff or generic advice."""

    try:
        review = gemini_client.generate(prompt)
        return {"review": review}
    except Exception as e:
        return {"error": f"Gemini error: {e}"}, 502
