# Personal OS

A mobile-first personal assistant app: tasks, alarms, notes/diary, spaced repetition, and AI chat — all backed by Firebase with real-time sync. Built with Flutter, targeting Android now and Windows desktop later.

---

## Features

### Tasks & Accountability
- Create, edit, and complete tasks with title, due date, priority (low/medium/high), and notes
- **Subtasks** — break work into steps within a task
- **Tags** — organize tasks by category (custom tag colors)
- **Recurrence** — daily or weekly repeat with weekday selection
- **Escalating reminders** — linked alarm retries at 5min → 15min → 1hr; gives up after the last rung
- **Capped snoozes** — max 3 snoozes per alarm cycle
- **Commitment text** — "Why this matters" shown on the alarm ring screen
- **Completion heatmap** — GitHub-style visual of task streaks
- **Stats screen** — completion rate, streak history, category breakdown

### Alarms
- Create standalone alarms with time, repeat days, and labels
- **Task-linked alarms** — set a reminder directly from the task form
- Real alarms that survive app kill via `flutter_local_notifications` + `android_alarm_manager_plus`
- Frosted-glass ring screen with glow animation, live clock, Stop/Snooze buttons

### Habits
- Track recurring habits (gym, reading, DSA, etc.) with frequency and rest days
- Cycle through statuses: done → skipped → missed → not marked
- **Streak tracking** with fire icon on tiles
- **Completion heatmap** per habit

### Calendar
- Month grid view showing both tasks and habits as colored indicator dots
- Tap a day to see its agenda (tasks first, then habits)
- Mark tasks complete and cycle habit status directly from the calendar

### Diary & Notes
- Create notes with freeform text
- **8 mood tags**: happy, sad, neutral, anxious, excited, calm, angry, grateful
- Filter notes by mood using chip selectors
- Create, edit, delete with swipe-to-delete

### Future Letters
- Write a letter to your future self with a resurface date
- When the date arrives, the app prompts you to write a follow-through reflection
- Letters sorted into Ready / Waiting / Reflected sections

### Brain Dump Inbox
- Zero-friction capture: tap "Dump", type your thought, done
- **Auto-sort with AI** — sends all entries to Gemini, which categorizes them into tasks, notes, diary, DSA problems, or people entries
- Review results in a dialog before accepting

### DSA Spaced Repetition
- Add solved DSA problems with optional LeetCode links
- **SM-2 algorithm** (same as Anki): intervals grow at 1 → 3 → 7 → 14 → 30+ days
- Review mode with 4 quality buttons: Again, Hard, Good, Easy
- Due queue shows overdue problems; full list shows all with next review dates

### AI Chat
- Conversational AI assistant powered by Gemini via the Flask backend
- Markdown rendering for code blocks and formatting
- Context-aware — maintains conversation history per session
- Accessible from the side drawer

### Today Screen
- Morning overview with personalized greeting ("Good morning, Alice")
- Stat cards: due today, overdue, current streak
- Due letters banner when future letters arrive
- Today's task list with square checkboxes matching the Tasks tab

### Settings & Profile
- Set your name (stored in Firestore, used for greetings)
- **4 theme palettes**: Aurora, Midnight Violet, Purple Empire, Warm Amber
- Light/dark mode toggle
- Tag management (create, rename, delete, recolor)

### Navigation
- **Bottom nav** (3 tabs): Today → Tasks → Diary
- **Side drawer**: Alarms, Habits, DSA Spaced Rep, Letters, Chat, Settings

---

## Architecture

```
personal_os/
├── lib/
│   ├── main.dart                    # App entry, Firebase init, global singletons
│   ├── firebase_options.dart        # Firebase config (auto-generated)
│   ├── models/                      # Data models (Firestore ↔ Dart)
│   │   ├── tasks/task.dart
│   │   ├── alarms/alarm.dart
│   │   ├── habits/habit.dart
│   │   ├── notes/note.dart, future_letter.dart, brain_dump.dart
│   │   ├── dsa/dsa_problem.dart
│   │   └── tags/tag.dart
│   ├── services/                    # Firestore CRUD + business logic
│   │   ├── tasks/task_service.dart
│   │   ├── alarms/alarm_service.dart, alarm_ring_listener.dart
│   │   ├── habits/habit_service.dart
│   │   ├── notes/note_service.dart, future_letter_service.dart, brain_dump_service.dart
│   │   ├── dsa/dsa_problem_service.dart
│   │   ├── api/api_service.dart     # Talks to Flask backend
│   │   ├── auth_service.dart
│   │   ├── profile_service.dart
│   │   ├── tags/tag_service.dart
│   │   └── native_bridge.dart       # Android platform channel
│   ├── screens/                     # UI screens
│   │   ├── home_shell.dart          # Bottom nav + drawer
│   │   ├── today/today_screen.dart
│   │   ├── tasks/task_list_page.dart, task_form_screen.dart, task_stats_screen.dart
│   │   ├── alarms/alarm_list_screen.dart, alarm_form_screen.dart, alarm_ring_screen.dart
│   │   ├── habits/habit_list_page.dart
│   │   ├── calendar/calendar_screen.dart
│   │   ├── notes/note_list_page.dart, note_form_screen.dart, brain_dump_capture_sheet.dart
│   │   ├── notes/future_letter_list_page.dart, future_letter_form_screen.dart, future_letter_reflect_screen.dart
│   │   ├── dsa/dsa_screen.dart
│   │   ├── chat/chat_screen.dart
│   │   ├── auth/login_screen.dart, auth_gate.dart
│   │   └── settings/settings_screen.dart, tags/tag_management_screen.dart
│   ├── widgets/                     # Reusable UI components
│   │   ├── tasks/task_tile.dart, day_agenda_tile.dart, subtask_list.dart, tag_section.dart
│   │   ├── tasks/completion_heatmap.dart, completion_history_sheet.dart
│   │   ├── alarms/time_wheel_picker.dart, alarm_ring_widgets.dart
│   │   ├── calendar/month_grid.dart, calendar_widgets.dart
│   │   ├── habits/habit_tile.dart
│   │   └── common/theme_toggle_switch.dart
│   ├── theme/app_theme.dart         # 4 palettes, light/dark themes, semantic colors
│   └── utils/                       # Helpers
│       ├── date_utils.dart          # Greeting time-of-day, date formatting
│       └── task_stats.dart          # Completion rate, streak calculations
│
├── backend/                         # Flask AI backend
│   ├── app.py                       # Flask entry, CORS, health check
│   ├── config.py                    # Environment variable loading
│   ├── firebase_auth.py             # Token verification middleware
│   ├── gemini_client.py             # Gemini API wrapper
│   ├── routes/
│   │   ├── chat.py                  # POST /api/chat
│   │   └── auto_sort.py             # POST /api/auto-sort
│   ├── requirements.txt
│   └── .env.example
│
├── android/                         # Android platform config
├── ios/                             # iOS platform (not primary target)
├── assets/sounds/                   # Alarm sounds
└── pubspec.yaml
```

### Data Flow

```
Flutter App ←→ Firebase Firestore ←→ (real-time sync)
     ↕
Flask Backend ←→ Gemini API (chat, auto-sort)
     ↕
Firebase Auth (ID token verification)
```

- **Firestore** handles everyday data sync (tasks, notes, habits, streaks) — no backend code needed
- **Flask backend** handles anything needing hidden API keys (LLM calls) — keys never ship inside the Flutter app

---

## Tech Stack

| Layer | Technology | Why |
|---|---|---|
| Frontend | Flutter (Dart) | One codebase for Android + Windows desktop |
| Database | Firebase Firestore | Real-time sync, offline support, no backend code for basic CRUD |
| Auth | Firebase Authentication | Google sign-in, email/password, guest |
| AI Backend | Flask (Python) | Reuses existing Flask skills, easy to deploy |
| LLM | Google Gemini | Free tier generous for personal use |
| Hosting | Render (free tier) | Simple Flask deployment |

### Flutter Dependencies

| Package | Purpose |
|---|---|
| `firebase_core`, `cloud_firestore`, `firebase_auth` | Firebase integration |
| `google_sign_in` | Google authentication |
| `alarm` | Real alarm scheduling |
| `permission_handler` | Runtime permissions |
| `wakelock_plus` | Keep screen on during alarm |
| `audioplayers` | Alarm sounds |
| `flutter_local_notifications` | Notification delivery |
| `http` | Backend API calls |
| `flutter_markdown` | Chat message rendering |
| `shared_preferences` | Local settings cache |
| `intl` | Date/time formatting |
| `file_picker` | File selection (future use) |

### Backend Dependencies

| Package | Purpose |
|---|---|
| `flask` | Web framework |
| `flask-cors` | Cross-origin requests from Flutter |
| `firebase-admin` | Token verification |
| `google-generativeai` | Gemini API client |
| `gunicorn` | Production WSGI server |

---

## Setup

### Prerequisites
- Flutter SDK (`C:\flutter\bin` or equivalent)
- Android Studio (for SDK, not as editor)
- VS Code with Flutter + Dart extensions
- Python 3.10+
- A Firebase project (Authentication + Firestore enabled)
- A Gemini API key ([get one here](https://aistudio.google.com/apikey))

### Flutter App

```bash
# Clone and enter the project
cd personal_os

# Install dependencies
flutter pub get

# Run on connected device
flutter run -d <device-id>

# Build debug APK
flutter build apk --debug
```

### Firebase Setup

1. Create a project at [console.firebase.google.com](https://console.firebase.google.com)
2. Register an Android app, download `google-services.json` → place in `android/app/`
3. Enable Authentication: Google sign-in + Email/Password
4. Create Firestore Database (start in test mode, then deploy security rules)
5. Add SHA-1 fingerprint to Firebase console (for Google sign-in on device)
6. Re-download `google-services.json` after any console change

### Flask Backend

```bash
cd backend

# Create virtual environment
python -m venv venv
source venv/bin/activate  # or venv\Scripts\activate on Windows

# Install dependencies
pip install -r requirements.txt

# Configure
cp .env.example .env
# Edit .env with your GEMINI_API_KEY and GOOGLE_APPLICATION_CREDENTIALS path

# Run locally
python app.py
# → http://localhost:5000

# Health check
curl http://localhost:5000/api/health
```

### Deploy Backend to Render

1. Push the repo to GitHub
2. Create a new Web Service on [render.com](https://render.com)
3. Settings:
   - **Build command**: `pip install -r requirements.txt`
   - **Start command**: `gunicorn app:app`
   - **Environment**: Python 3.11+
4. Add environment variables:
   - `GEMINI_API_KEY` — your Gemini API key
   - `GOOGLE_APPLICATION_CREDENTIALS` — paste the entire service account JSON contents
5. Deploy — get your URL (e.g., `https://personal-os-backend.onrender.com`)
6. Update `lib/services/api/api_service.dart` with your Render URL

---

## Commands

```bash
# Run on phone
flutter run -d <device-id>

# Run on Windows desktop (Phase 5)
flutter run -d windows

# Build debug APK
flutter build apk --debug

# Analyze for issues
dart analyze lib

# Install Flutter dependencies
flutter pub get

# Run Flask backend locally
cd backend && python app.py
```

---

## Project Phases

| Phase | Status | Features |
|---|---|---|
| **Phase 1** — Scheduling + Alarms | ✅ Complete | Tasks, alarms, escalating reminders, streaks, commitment text |
| **Phase 2** — Notes + Reflection | ✅ Complete | Diary, mood tags, future letters, brain dump, DSA spaced rep, calendar |
| **Phase 3** — Anti-Doom-Scrolling | 🔲 Planned | Android UsageStatsManager, interrupt screen |
| **Phase 4** — AI Brain | 🟡 In progress | Flask backend, Gemini chat, auto-sort. Remaining: people analysis, semantic memory, voice, auto-reviews |
| **Phase 5** — Desktop Port | 🔲 Planned | `flutter build windows` (needs Visual Studio C++ workload) |

---

## Firestore Data Model

All collections scoped to `users/{uid}/` via security rules.

| Collection | Fields | Phase |
|---|---|---|
| `tasks` | title, dueDate, repeatType, repeatDays, priority, subtasks, notes, tagId, completionLog, streakCount, linkedAlarmId, commitmentText | 1 |
| `alarms` | id, label, hour, minute, type, repeatDays, oneTimeDate, isEnabled, linkedTaskId | 1 |
| `habits` | name, frequency, restDays, log, currentStreak | 1 |
| `notes` | text, mood, createdAt | 2 |
| `future_letters` | content, writtenDate, resurfaceDate, reflection, reflected | 2 |
| `braindump` | text, createdAt | 2 |
| `dsa_problems` | name, link, solvedDate, nextReviewDate, intervalDays, easeFactor, reviewCount | 2 |
| `tags` | name, color | 1 |
| `meta/profile` | name | 1 |

---

## Security

- **Firebase Auth** locks every collection — `request.auth.uid == userId` enforced via security rules
- **API keys** live only on the Flask backend (never inside the Flutter app — APKs can be decompiled)
- **Token verification** — every backend request verifies the Firebase ID token before touching data
- **HTTPS** between app and backend
- **Input sanitization** on anything stored or sent to the LLM

---

## Free Tier Limits

| Service | Free Tier | Solo Use Reality |
|---|---|---|
| Firestore | 50K reads/day, 20K writes/day, 1GB | Very unlikely to hit |
| Firebase Auth | Unlimited at this scale | No concern |
| Gemini API | Rate-limited per minute | Fine for conversational use |
| Render | 750 hrs/month | Enough for a personal backend |

---

## License

Personal project — not open source.
