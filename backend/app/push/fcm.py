from __future__ import annotations

import json
import os
from functools import lru_cache
from typing import Any, Dict, Optional

import firebase_admin
from firebase_admin import credentials, messaging

from ..settings import settings


def init_firebase_app() -> None:
    """Public entry: initialize Firebase Admin (FCM, Firestore, etc.)."""
    _init_firebase()


@lru_cache(maxsize=1)
def _init_firebase() -> None:
    if firebase_admin._apps:
        return

    if not settings.has_firebase_credentials():
        raise RuntimeError(
            "Missing Firebase credentials. Set FIREBASE_SERVICE_ACCOUNT_PATH "
            "or FIREBASE_SERVICE_ACCOUNT_JSON."
        )

    if settings.resolved_service_account_path:
        path = settings.resolved_service_account_path
        if not os.path.isfile(path):
            raise FileNotFoundError(f"Service account file not found: {path}")
        cred = credentials.Certificate(path)
    else:
        raw = settings.firebase_service_account_json.strip()
        try:
            data = json.loads(raw)
            cred = credentials.Certificate(data)
        except json.JSONDecodeError:
            path = os.path.expanduser(raw)
            if not os.path.isfile(path):
                hint = raw if len(raw) <= 120 else f"{raw[:117]}..."
                raise FileNotFoundError(
                    "FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON and not an existing file path: "
                    f"{hint}"
                ) from None
            cred = credentials.Certificate(path)

    firebase_admin.initialize_app(cred)


def send_to_token(
    *,
    token: str,
    title: str,
    body: str,
    data: Optional[Dict[str, str]] = None,
) -> str:
    _init_firebase()
    msg = messaging.Message(
        token=token,
        notification=messaging.Notification(title=title, body=body),
        data=data or None,
        apns=messaging.APNSConfig(
            headers={"apns-priority": "10"},
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    sound="default",
                )
            ),
        ),
    )
    return messaging.send(msg)

