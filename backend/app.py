"""Personal OS — Flask backend.

Run locally:
    cd backend
    pip install -r requirements.txt
    cp .env.example .env  # then fill in your keys
    python app.py

Deploy to Render:
    - Build command: pip install -r requirements.txt
    - Start command: gunicorn app:app
    - Environment variables: GEMINI_API_KEY, GOOGLE_APPLICATION_CREDENTIALS
"""

import os
from flask import Flask, jsonify
from flask_cors import CORS
from rate_limit import limiter

from firebase_auth import init_firebase
from routes.chat import chat_bp
from routes.auto_sort import auto_sort_bp
from routes.analyze_person import analyze_person_bp
from routes.weekly_review import weekly_review_bp
from routes.semantic_search import semantic_search_bp


def create_app() -> Flask:
    app = Flask(__name__)
    CORS(app, origins=["*"])  # tighten in production

    limiter.init_app(app)

    # Firebase Admin SDK — only needed for token verification
    try:
        init_firebase()
    except Exception as e:
        print(f"⚠️  Firebase init failed (chat will still work without auth): {e}")

    # Register blueprints
    app.register_blueprint(chat_bp)
    app.register_blueprint(auto_sort_bp)
    app.register_blueprint(analyze_person_bp)
    app.register_blueprint(weekly_review_bp)
    app.register_blueprint(semantic_search_bp)

    # Health check
    @app.route("/api/health")
    def health():
        return jsonify({"status": "ok", "service": "personal-os-backend"})

    return app


app = create_app()

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)
