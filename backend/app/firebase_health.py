from __future__ import annotations

import json
from typing import Any

import firebase_admin
from firebase_admin import firestore

from .push.fcm import init_firebase_app
from .settings import settings


def get_firebase_health() -> dict[str, Any]:
    """
    For debugging: see whether Admin SDK is configured and Firestore is readable.
    """
    out: dict[str, Any] = {
        "credentials_configured": settings.has_firebase_credentials(),
        "key_source": settings.firebase_admin_key_source(),
        "where_to_look": (
            "Console → Build → Firestore Database (not Realtime Database). "
            "Collection: `users`."
        ),
    }
    if not settings.has_firebase_credentials():
        out["status"] = "unconfigured"
        out["hint"] = (
            "Set FIREBASE_SERVICE_ACCOUNT_PATH in `backend/.env` to your Admin SDK JSON, "
            "or pass FIREBASE_SERVICE_ACCOUNT_JSON. Restart uvicorn after editing."
        )
        return out
    try:
        init_firebase_app()
    except Exception as e:
        out["status"] = "init_error"
        out["error"] = str(e)
        return out

    try:
        app = firebase_admin.get_app()
        out["gcp_project_id"] = getattr(app, "project_id", None) or _project_id_from_credentials()
    except Exception:
        out["gcp_project_id"] = _project_id_from_credentials()

    try:
        db = firestore.client()
        next(db.collection("users").limit(1).stream(), None)
        out["status"] = "ok"
        out["firestore"] = "reachable"
    except Exception as e:
        out["status"] = "firestore_error"
        out["error"] = str(e)
    return out


def _project_id_from_credentials() -> str | None:
    path = settings.resolved_service_account_path
    if not path:
        raw = (settings.firebase_service_account_json or "").strip()
        if raw.startswith("{"):
            try:
                return str(json.loads(raw).get("project_id", "") or "")
            except json.JSONDecodeError:
                return None
        return None
    try:
        with open(path, encoding="utf-8") as f:
            return str(json.load(f).get("project_id", "") or "")
    except OSError:
        return None
