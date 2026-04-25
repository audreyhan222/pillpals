import os
from pathlib import Path

from pydantic import PrivateAttr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# backend/ directory (parent of `app/`)
_BACKEND_ROOT = Path(__file__).resolve().parent.parent
# Later files override earlier. Put `backend/.env` last so it wins over repo-root `.env`.
_ENV_FILES: tuple[str, ...] = (
    str(Path.cwd() / ".env"),
    str(_BACKEND_ROOT / ".env"),
)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=_ENV_FILES,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "pillpals-backend"
    secret_key: str = "dev-secret-change-me"
    access_token_exp_minutes: int = 60 * 24 * 7
    database_url: str = "sqlite:///./pillpals.db"
    cors_allow_origins: str = "*"

    # Firebase Admin (FCM, Firestore). Prefer a file path in dev:
    #   FIREBASE_SERVICE_ACCOUNT_PATH=~/path/to-adminsdk.json
    # Or inline JSON in env (CI): FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
    # If both are set, FIREBASE_SERVICE_ACCOUNT_PATH wins.
    firebase_service_account_path: str = ""
    # Either a path to a Firebase service account JSON file, or the full JSON string.
    firebase_service_account_json: str = ""
    enable_dev_push_endpoints: bool = True

    _resolved_service_account_path: str | None = PrivateAttr(default=None)

    @model_validator(mode="after")
    def _normalize_firebase_path(self) -> "Settings":
        p = (self.firebase_service_account_path or "").strip()
        if p:
            self._resolved_service_account_path = os.path.expanduser(p)
        return self

    def firebase_admin_key_source(self) -> str:
        """Non-secret hint for logs: path, inline-json, or empty."""
        if self._resolved_service_account_path:
            return f"file:{self._resolved_service_account_path}"
        if (self.firebase_service_account_json or "").strip():
            return "inline_json"
        return "none"

    def has_firebase_credentials(self) -> bool:
        return bool(self._resolved_service_account_path) or bool(
            (self.firebase_service_account_json or "").strip()
        )

    @property
    def resolved_service_account_path(self) -> str | None:
        return self._resolved_service_account_path


settings = Settings()

