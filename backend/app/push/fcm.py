from __future__ import annotations

import json
from functools import lru_cache
from typing import Any, Dict, Optional

import firebase_admin
from firebase_admin import credentials, messaging

from ..settings import settings


@lru_cache(maxsize=1)
def _init_firebase() -> None:
    if firebase_admin._apps:
        return

    if not settings.firebase_service_account_json:
        raise RuntimeError("Missing FIREBASE_SERVICE_ACCOUNT_JSON.")

    raw = settings.firebase_service_account_json.strip()
    try:
        # Allow passing the full JSON contents via env var.
        data = json.loads(raw)
        cred = credentials.Certificate(data)
    except json.JSONDecodeError:
        # Or a file path.
        cred = credentials.Certificate(raw)

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

