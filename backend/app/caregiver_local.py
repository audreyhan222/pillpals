from __future__ import annotations

import re
import logging
from typing import Any

from google.cloud.firestore import SERVER_TIMESTAMP
from firebase_admin import firestore

from .push.fcm import init_firebase_app
from .settings import settings

log = logging.getLogger(__name__)

CAREGIVERS_COLLECTION = "caregivers"
# IANA-reserved example domain (OK for locally-assigned auth rows).
EMAIL_DOMAIN = "caregiver.example.com"


def caregiver_doc_id(username: str) -> str:
    u = (username or "").strip()
    if not u:
        raise ValueError("empty username")
    return u.replace("/", "_")


def derived_caregiver_email(doc_id: str) -> str:
    """Synthetic email for SQLite AuthUser; must pass EmailStr validation. Preserves case for uniqueness."""
    local = re.sub(r"[^a-zA-Z0-9._+-]+", ".", doc_id.strip())
    local = re.sub(r"\.+", ".", local).strip(".")
    if not local:
        local = "u"
    local = local[:64]
    return f"{local}@{EMAIL_DOMAIN}"


def _db():
    if not settings.has_firebase_credentials():
        raise RuntimeError("Firebase credentials are not configured (needed for caregiver Firestore).")
    init_firebase_app()
    return firestore.client()


def get_caregiver_doc(username: str) -> Any | None:
    doc_id = caregiver_doc_id(username)
    return _db().collection(CAREGIVERS_COLLECTION).document(doc_id).get()


def create_caregiver_doc(*, username: str, password: str, name: str) -> str:
    doc_id = caregiver_doc_id(username)
    ref = _db().collection(CAREGIVERS_COLLECTION).document(doc_id)
    if ref.get().exists:
        raise ValueError("username_taken")
    ref.set(
        {
            "username": username.strip(),
            "name": name.strip(),
            "password": password,
            "createdAt": SERVER_TIMESTAMP,
        }
    )
    return doc_id


def verify_caregiver_password(d: Any, password: str) -> bool:
    if not d.exists:
        return False
    data = d.to_dict() or {}
    stored = data.get("password")
    if not isinstance(stored, str):
        return False
    return stored == password


def delete_caregiver_doc(*, username: str) -> None:
    doc_id = caregiver_doc_id(username)
    _db().collection(CAREGIVERS_COLLECTION).document(doc_id).delete()
