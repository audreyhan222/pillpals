from __future__ import annotations

import logging
import re

from google.cloud.firestore import SERVER_TIMESTAMP
from firebase_admin import firestore

from .push.fcm import init_firebase_app
from .settings import settings

log = logging.getLogger(__name__)

# Firestore document ids cannot contain "/" — normalize email for use as id.
_invalid_doc_id = re.compile(r"[/]")


def upsert_user_document(
    *,
    email: str,
    name: str,
    role: str,
    auth_user_id: int | None = None,
) -> bool:
    """
    Write a user profile to Firestore using the Admin SDK (bypasses client security rules).
    No-ops if Firebase credentials are not configured.
    """
    if not settings.has_firebase_credentials():
        log.warning(
            "Firebase credentials not set (FIREBASE_SERVICE_ACCOUNT_PATH or "
            "FIREBASE_SERVICE_ACCOUNT_JSON); skipping Firestore user sync"
        )
        return False
    if not name.strip() or not role.strip():
        return False
    try:
        init_firebase_app()
    except Exception as e:
        log.warning("Firebase init failed; skipping Firestore sync: %s", e)
        return False

    db = firestore.client()
    local = email.strip().lower()
    doc_id = _invalid_doc_id.sub("_", local)
    if not doc_id:
        return False
    ref = db.collection("users").document(doc_id)
    payload: dict = {
        "email": email.strip(),
        "name": name.strip(),
        "role": role.strip(),
        "createdAt": SERVER_TIMESTAMP,
    }
    if auth_user_id is not None:
        payload["authUserId"] = auth_user_id
    ref.set(payload, merge=True)
    log.info("Firestore users/%s synced (email=%s role=%s authUserId=%s)", doc_id, email, role, auth_user_id)
    return True
