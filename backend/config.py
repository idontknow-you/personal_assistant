import os
from dotenv import load_dotenv

load_dotenv()


class Config:
    GEMINI_API_KEY: str = os.environ.get("GEMINI_API_KEY", "")
    GEMINI_MODEL: str = os.environ.get("GEMINI_MODEL", "gemini-flash-latest")
    GOOGLE_APPLICATION_CREDENTIALS: str = os.environ.get(
        "GOOGLE_APPLICATION_CREDENTIALS", ""
    )
    SECRET_KEY: str = os.environ.get("SECRET_KEY", os.urandom(24).hex())


config = Config()
