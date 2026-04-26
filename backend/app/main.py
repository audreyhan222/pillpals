from __future__ import annotations

import json
import logging
import random
import re
import string
from datetime import datetime, timedelta, timezone
from typing import List

import httpx
from dotenv import dotenv_values
from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlmodel import Session, select

from .auth import (
    create_access_token,
    get_auth_user_by_email,
    get_current_auth_user,
    hash_password,
    verify_password,
)
from .db import get_session, init_db
from .models import AuthUser, Caregiver, DevicePushToken, DoseLog, DoseStatus, Medication, Role, User
from .schemas import (
    AiSuggestionOut,
    CaregiverAlertIn,
    CaregiverOut,
    CaregiverProfileIn,
    DoseConfirmIn,
    DoseLogOut,
    InsightOut,
    LoginIn,
    MedicationCreateIn,
    MedicationOut,
    ProfileUpsertIn,
    ScanMedicationIn,
    ScanMedicationOut,
    SignupIn,
    TokenOut,
    UserOut,
    CaregiverLocalLoginIn,
    CaregiverLocalSignupIn,
    LinkCaregiverIn,
    PushTokenIn,
    PushTokenOut,
    DevPushIn,
)
from .settings import settings
from .push.fcm import send_to_token
from .firebase_health import get_firebase_health
from .caregiver_local import (
    caregiver_doc_id,
    create_caregiver_doc,
    delete_caregiver_doc,
    derived_caregiver_email,
    get_caregiver_doc,
    verify_caregiver_password,
)

log = logging.getLogger(__name__)


def _scan_medication_forced_overrides() -> tuple[str, str, str]:
    """
    Dev-only helper: read overrides from backend/.env on each request.
    This avoids needing to restart the server when toggling debug overrides.
    """
    try:
        values = dotenv_values(".env") or {}
    except Exception:
        values = {}
    name = (values.get("SCAN_MEDICATION_FORCE_NAME") or "").strip()
    dosage = (values.get("SCAN_MEDICATION_FORCE_DOSAGE") or "").strip()
    instructions = (values.get("SCAN_MEDICATION_FORCE_INSTRUCTIONS") or "").strip()
    return name, dosage, instructions

app = FastAPI(title=settings.app_name)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.cors_allow_origins] if settings.cors_allow_origins != "*" else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup():
    init_db()
    log.info("Firebase admin key: %s", settings.firebase_admin_key_source())


@app.get("/health")
def health():
    return {"ok": True}


@app.get("/health/firebase")
def health_firebase():
    """Check Admin SDK + Firestore; see `where_to_look` (Firestore, not Realtime DB)."""
    return get_firebase_health()


@app.post("/push/token", response_model=PushTokenOut)
def register_push_token(
    payload: PushTokenIn,
    auth_user: AuthUser = Depends(get_current_auth_user),
    session: Session = Depends(get_session),
):
    token = payload.token.strip()
    if not token:
        raise HTTPException(status_code=400, detail="Missing token.")

    existing = session.exec(select(DevicePushToken).where(DevicePushToken.fcm_token == token)).first()
    now = datetime.utcnow()
    if existing:
        existing.auth_user_id = auth_user.id  # type: ignore[arg-type]
        existing.platform = payload.platform
        existing.last_seen_at = now
        session.add(existing)
        session.commit()
        return PushTokenOut(ok=True)

    session.add(
        DevicePushToken(
            auth_user_id=auth_user.id,  # type: ignore[arg-type]
            platform=payload.platform,
            fcm_token=token,
            created_at=now,
            last_seen_at=now,
        )
    )
    session.commit()
    return PushTokenOut(ok=True)


@app.post("/dev/push")
def dev_push(
    payload: DevPushIn,
    auth_user: AuthUser = Depends(get_current_auth_user),
    session: Session = Depends(get_session),
):
    if not settings.enable_dev_push_endpoints:
        raise HTTPException(status_code=404, detail="Not found.")

    tokens = session.exec(
        select(DevicePushToken).where(DevicePushToken.auth_user_id == auth_user.id)
    ).all()
    if not tokens:
        raise HTTPException(status_code=400, detail="No push tokens registered for this user.")

    data: dict[str, str] | None = None
    if payload.data:
        data = {str(k): str(v) for k, v in payload.data.items()}

    results = []
    for t in tokens:
        try:
            msg_id = send_to_token(
                token=t.fcm_token,
                title=payload.title,
                body=payload.body,
                data=data,
            )
            results.append({"token": t.fcm_token, "message_id": msg_id})
        except Exception as e:
            results.append({"token": t.fcm_token, "error": str(e)})

    return {"sent": len([r for r in results if "message_id" in r]), "results": results}


def _invite_code() -> str:
    return "".join(random.choices(string.ascii_uppercase + string.digits, k=6))


def _ensure_max_10_meds(session: Session, user_id: int) -> None:
    count = session.exec(select(Medication).where(Medication.user_id == user_id)).all()
    if len(count) >= 10:
        raise HTTPException(status_code=400, detail="Medication limit reached (max 10).")


@app.post("/auth/signup", response_model=TokenOut)
def signup(payload: SignupIn, session: Session = Depends(get_session)):
    existing = get_auth_user_by_email(session, payload.email)
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered.")
    auth_user = AuthUser(email=payload.email, password_hash=hash_password(payload.password))
    session.add(auth_user)
    session.commit()
    session.refresh(auth_user)
    firestore_user_sync: str | None = "skipped"
    if payload.name and payload.account_role:
        try:
            from .firestore_sync import upsert_user_document

            if upsert_user_document(
                email=payload.email,
                name=payload.name,
                role=payload.account_role,
                auth_user_id=auth_user.id,
            ):
                firestore_user_sync = "ok"
            else:
                firestore_user_sync = "failed_or_no_credentials"
        except Exception:
            log.exception("Firestore user sync failed after signup (auth user still created)")
            firestore_user_sync = "error"
    token = create_access_token(subject=str(auth_user.id), expires_minutes=settings.access_token_exp_minutes)
    return TokenOut(access_token=token, firestore_user_sync=firestore_user_sync)


@app.post("/auth/login", response_model=TokenOut)
def login(payload: LoginIn, session: Session = Depends(get_session)):
    auth_user = get_auth_user_by_email(session, payload.email)
    if not auth_user or not verify_password(payload.password, auth_user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password.")
    token = create_access_token(subject=str(auth_user.id), expires_minutes=settings.access_token_exp_minutes)
    return TokenOut(access_token=token)


@app.post("/auth/caregiver/signup", response_model=TokenOut)
def caregiver_signup_with_firestore_doc(
    payload: CaregiverLocalSignupIn, session: Session = Depends(get_session)
):
    """
    Creates `caregivers/{username}` in Firestore with a `password` field (MVP) and a matching
    local API user (JWT) using a derived synthetic email.
    """
    if not settings.has_firebase_credentials():
        raise HTTPException(
            status_code=503,
            detail="Set FIREBASE_SERVICE_ACCOUNT_PATH in backend/.env for caregiver sign-up.",
        )
    try:
        doc_id = caregiver_doc_id(payload.username)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    email = derived_caregiver_email(doc_id)
    if get_auth_user_by_email(session, email):
        raise HTTPException(status_code=400, detail="That username is already registered.")

    created_fs = False
    try:
        create_caregiver_doc(
            username=payload.username,
            password=payload.password,
            name=payload.name,
        )
        created_fs = True
    except ValueError as e:
        if str(e) == "username_taken":
            raise HTTPException(status_code=400, detail="That username is already taken.")
        raise

    try:
        auth_user = AuthUser(email=email, password_hash=hash_password(payload.password))
        session.add(auth_user)
        session.commit()
        session.refresh(auth_user)
    except Exception:
        if created_fs:
            try:
                delete_caregiver_doc(username=payload.username)
            except Exception:
                log.exception("Failed to delete Firestore caregiver doc after database error")
        raise

    try:
        from .firestore_sync import upsert_user_document

        upsert_user_document(
            email=email,
            name=payload.name,
            role="caregiver",
            auth_user_id=auth_user.id,
        )
    except Exception:
        log.exception("Optional Firestore users/ mirror after caregiver signup")
    token = create_access_token(subject=str(auth_user.id), expires_minutes=settings.access_token_exp_minutes)
    return TokenOut(access_token=token, firestore_user_sync="ok")


@app.post("/auth/caregiver/login", response_model=TokenOut)
def caregiver_login_with_firestore_doc(
    payload: CaregiverLocalLoginIn, session: Session = Depends(get_session)
):
    if not settings.has_firebase_credentials():
        raise HTTPException(
            status_code=503,
            detail="Set FIREBASE_SERVICE_ACCOUNT_PATH in backend/.env for caregiver sign-in.",
        )
    try:
        doc_id = caregiver_doc_id(payload.username)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    d = get_caregiver_doc(payload.username)
    if not verify_caregiver_password(d, payload.password):
        raise HTTPException(status_code=401, detail="Invalid username or password.")
    email = derived_caregiver_email(doc_id)
    auth_user = get_auth_user_by_email(session, email)
    if not auth_user:
        raise HTTPException(
            status_code=401,
            detail="This username has no app account. Use Sign up to create one.",
        )
    if not verify_password(payload.password, auth_user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid username or password.")
    token = create_access_token(subject=str(auth_user.id), expires_minutes=settings.access_token_exp_minutes)
    return TokenOut(access_token=token)


@app.post("/users", response_model=UserOut)
def upsert_user_profile(
    payload: ProfileUpsertIn,
    auth_user: AuthUser = Depends(get_current_auth_user),
    session: Session = Depends(get_session),
):
    existing = session.exec(select(User).where(User.auth_user_id == auth_user.id)).first()
    if existing:
        existing.name = payload.name
        existing.age = payload.age
        existing.phone = payload.phone
        existing.role = payload.role
        existing.emergency_info = payload.emergency_info
        session.add(existing)
        session.commit()
        session.refresh(existing)
        return UserOut(
            id=existing.id,
            name=existing.name,
            age=existing.age,
            phone=existing.phone,
            role=existing.role,
            caregiver_id=existing.caregiver_id,
            emergency_info=existing.emergency_info,
            invite_code=existing.invite_code,
        )

    user = User(
        auth_user_id=auth_user.id,
        name=payload.name,
        age=payload.age,
        phone=payload.phone,
        role=payload.role,
        emergency_info=payload.emergency_info,
        invite_code=_invite_code(),
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    return UserOut(
        id=user.id,
        name=user.name,
        age=user.age,
        phone=user.phone,
        role=user.role,
        caregiver_id=user.caregiver_id,
        emergency_info=user.emergency_info,
        invite_code=user.invite_code,
    )


@app.get("/users/{id}", response_model=UserOut)
def get_user(
    id: int,
    auth_user: AuthUser = Depends(get_current_auth_user),
    session: Session = Depends(get_session),
):
    user = session.get(User, id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")
    if user.auth_user_id != auth_user.id:
        raise HTTPException(status_code=403, detail="Forbidden.")
    return UserOut(
        id=user.id,
        name=user.name,
        age=user.age,
        phone=user.phone,
        role=user.role,
        caregiver_id=user.caregiver_id,
        emergency_info=user.emergency_info,
        invite_code=user.invite_code,
    )


@app.post("/caregivers/profile", response_model=CaregiverOut)
def upsert_caregiver_profile(
    payload: CaregiverProfileIn,
    auth_user: AuthUser = Depends(get_current_auth_user),
    session: Session = Depends(get_session),
):
    caregiver = session.exec(select(Caregiver).where(Caregiver.auth_user_id == auth_user.id)).first()
    if caregiver:
        caregiver.name = payload.name
        caregiver.phone = payload.phone
        caregiver.relationship = payload.relationship
        session.add(caregiver)
        session.commit()
        session.refresh(caregiver)
        return CaregiverOut(id=caregiver.id, name=caregiver.name, phone=caregiver.phone, relationship=caregiver.relationship)

    caregiver = Caregiver(
        auth_user_id=auth_user.id,
        name=payload.name,
        phone=payload.phone,
        relationship=payload.relationship,
    )
    session.add(caregiver)
    session.commit()
    session.refresh(caregiver)
    return CaregiverOut(id=caregiver.id, name=caregiver.name, phone=caregiver.phone, relationship=caregiver.relationship)


@app.post("/caregivers/link")
def caregiver_link_user(
    payload: LinkCaregiverIn,
    auth_user: AuthUser = Depends(get_current_auth_user),
    session: Session = Depends(get_session),
):
    caregiver = session.exec(select(Caregiver).where(Caregiver.auth_user_id == auth_user.id)).first()
    if not caregiver:
        raise HTTPException(status_code=400, detail="Create caregiver profile first.")

    user = session.exec(select(User).where(User.invite_code == payload.invite_code)).first()
    if not user:
        raise HTTPException(status_code=404, detail="Invite code not found.")
    if user.role != Role.elderly:
        raise HTTPException(status_code=400, detail="Invite code is not for an elderly user.")
    user.caregiver_id = caregiver.id
    session.add(user)
    session.commit()
    return {"linked": True, "user_id": user.id, "caregiver_id": caregiver.id}


@app.post("/medications", response_model=MedicationOut)
def create_medication(
    payload: MedicationCreateIn,
    auth_user: AuthUser = Depends(get_current_auth_user),
    session: Session = Depends(get_session),
):
    user = session.get(User, payload.user_id)
    if not user or user.auth_user_id != auth_user.id:
        raise HTTPException(status_code=403, detail="Forbidden.")
    _ensure_max_10_meds(session, payload.user_id)

    med = Medication(
        user_id=payload.user_id,
        name=payload.name,
        dosage=payload.dosage,
        instructions=payload.instructions,
        pill_type=payload.pill_type,
        scheduled_times_json=json.dumps(payload.scheduled_times),
        reminder_window_minutes=payload.reminder_window_minutes,
    )
    session.add(med)
    session.commit()
    session.refresh(med)
    return MedicationOut(
        id=med.id,
        user_id=med.user_id,
        name=med.name,
        dosage=med.dosage,
        instructions=med.instructions,
        pill_type=med.pill_type,
        scheduled_times=json.loads(med.scheduled_times_json),
        reminder_window_minutes=med.reminder_window_minutes,
    )


@app.get("/medications/{user_id}", response_model=List[MedicationOut])
def list_medications(
    user_id: int,
    auth_user: AuthUser = Depends(get_current_auth_user),
    session: Session = Depends(get_session),
):
    user = session.get(User, user_id)
    if not user or user.auth_user_id != auth_user.id:
        raise HTTPException(status_code=403, detail="Forbidden.")
    meds = session.exec(select(Medication).where(Medication.user_id == user_id)).all()
    return [
        MedicationOut(
            id=m.id,
            user_id=m.user_id,
            name=m.name,
            dosage=m.dosage,
            instructions=m.instructions,
            pill_type=m.pill_type,
            scheduled_times=json.loads(m.scheduled_times_json),
            reminder_window_minutes=m.reminder_window_minutes,
        )
        for m in meds
    ]


@app.put("/medications/{med_id}", response_model=MedicationOut)
def update_medication(
    med_id: int,
    payload: MedicationCreateIn,
    auth_user: AuthUser = Depends(get_current_auth_user),
    session: Session = Depends(get_session),
):
    med = session.get(Medication, med_id)
    if not med:
        raise HTTPException(status_code=404, detail="Medication not found.")
    user = session.get(User, med.user_id)
    if not user or user.auth_user_id != auth_user.id:
        raise HTTPException(status_code=403, detail="Forbidden.")

    med.name = payload.name
    med.dosage = payload.dosage
    med.instructions = payload.instructions
    med.pill_type = payload.pill_type
    med.scheduled_times_json = json.dumps(payload.scheduled_times)
    med.reminder_window_minutes = payload.reminder_window_minutes
    session.add(med)
    session.commit()
    session.refresh(med)
    return MedicationOut(
        id=med.id,
        user_id=med.user_id,
        name=med.name,
        dosage=med.dosage,
        instructions=med.instructions,
        pill_type=med.pill_type,
        scheduled_times=json.loads(med.scheduled_times_json),
        reminder_window_minutes=med.reminder_window_minutes,
    )


@app.delete("/medications/{med_id}")
def delete_medication(
    med_id: int,
    auth_user: AuthUser = Depends(get_current_auth_user),
    session: Session = Depends(get_session),
):
    med = session.get(Medication, med_id)
    if not med:
        raise HTTPException(status_code=404, detail="Medication not found.")
    user = session.get(User, med.user_id)
    if not user or user.auth_user_id != auth_user.id:
        raise HTTPException(status_code=403, detail="Forbidden.")
    session.delete(med)
    session.commit()
    return {"deleted": True}


@app.post("/dose/confirm", response_model=DoseLogOut)
def confirm_dose(
    payload: DoseConfirmIn,
    auth_user: AuthUser = Depends(get_current_auth_user),
    session: Session = Depends(get_session),
):
    med = session.get(Medication, payload.medication_id)
    if not med or med.user_id != payload.user_id:
        raise HTTPException(status_code=404, detail="Medication not found for user.")
    user = session.get(User, payload.user_id)
    if not user or user.auth_user_id != auth_user.id:
        raise HTTPException(status_code=403, detail="Forbidden.")

    taken_time = payload.taken_time or datetime.now(timezone.utc)
    scheduled = payload.scheduled_time
    delta = taken_time - scheduled
    status = DoseStatus.taken if delta <= timedelta(minutes=5) else DoseStatus.late

    log = DoseLog(
        medication_id=payload.medication_id,
        user_id=payload.user_id,
        scheduled_time=scheduled,
        taken_time=taken_time,
        status=status,
    )
    session.add(log)
    session.commit()
    session.refresh(log)
    return DoseLogOut(
        id=log.id,
        medication_id=log.medication_id,
        user_id=log.user_id,
        scheduled_time=log.scheduled_time,
        taken_time=log.taken_time,
        status=log.status,
    )


@app.get("/dose/history/{user_id}", response_model=List[DoseLogOut])
def dose_history(
    user_id: int,
    auth_user: AuthUser = Depends(get_current_auth_user),
    session: Session = Depends(get_session),
):
    user = session.get(User, user_id)
    if not user or user.auth_user_id != auth_user.id:
        raise HTTPException(status_code=403, detail="Forbidden.")
    logs = session.exec(select(DoseLog).where(DoseLog.user_id == user_id).order_by(DoseLog.scheduled_time.desc())).all()
    return [
        DoseLogOut(
            id=l.id,
            medication_id=l.medication_id,
            user_id=l.user_id,
            scheduled_time=l.scheduled_time,
            taken_time=l.taken_time,
            status=l.status,
        )
        for l in logs
    ]


def _bucket(dt: datetime) -> str:
    h = dt.hour
    if 5 <= h < 12:
        return "morning"
    if 12 <= h < 17:
        return "afternoon"
    if 17 <= h < 22:
        return "night"
    return "late_night"


@app.get("/insights/{user_id}", response_model=InsightOut)
def insights(
    user_id: int,
    auth_user: AuthUser = Depends(get_current_auth_user),
    session: Session = Depends(get_session),
):
    user = session.get(User, user_id)
    if not user or user.auth_user_id != auth_user.id:
        raise HTTPException(status_code=403, detail="Forbidden.")

    week_ago = datetime.now(timezone.utc) - timedelta(days=7)
    logs = session.exec(select(DoseLog).where(DoseLog.user_id == user_id, DoseLog.scheduled_time >= week_ago)).all()

    total_taken = sum(1 for l in logs if l.status in (DoseStatus.taken, DoseStatus.late))
    total_missed = sum(1 for l in logs if l.status == DoseStatus.missed)
    denom = max(1, len(logs))
    weekly_adherence = (total_taken / denom) * 100.0

    buckets = {"morning": 0, "afternoon": 0, "night": 0, "late_night": 0}
    missed_buckets = {"morning": 0, "afternoon": 0, "night": 0, "late_night": 0}
    for l in logs:
        b = _bucket(l.scheduled_time)
        buckets[b] += 1
        if l.status == DoseStatus.missed:
            missed_buckets[b] += 1

    most_missed = None
    if sum(missed_buckets.values()) > 0:
        most_missed = max(missed_buckets.items(), key=lambda kv: kv[1])[0]

    # Simple streak: consecutive days with no missed doses in logs (best-effort with available data)
    streak_days = 0
    today = datetime.now(timezone.utc).date()
    for i in range(0, 14):
        day = today - timedelta(days=i)
        day_logs = [l for l in logs if l.scheduled_time.date() == day]
        if not day_logs:
            continue
        if any(l.status == DoseStatus.missed for l in day_logs):
            break
        streak_days += 1

    return InsightOut(
        weekly_adherence_percent=round(weekly_adherence, 1),
        total_taken=total_taken,
        total_missed=total_missed,
        most_missed_time_bucket=most_missed,
        morning_vs_night={
            "morning": {"total": buckets["morning"], "missed": missed_buckets["morning"]},
            "night": {"total": buckets["night"], "missed": missed_buckets["night"]},
        },
        current_streak_days=streak_days,
    )


@app.get("/ai-suggestion/{user_id}", response_model=AiSuggestionOut)
def ai_suggestion(
    user_id: int,
    auth_user: AuthUser = Depends(get_current_auth_user),
    session: Session = Depends(get_session),
):
    user = session.get(User, user_id)
    if not user or user.auth_user_id != auth_user.id:
        raise HTTPException(status_code=403, detail="Forbidden.")

    week_ago = datetime.now(timezone.utc) - timedelta(days=14)
    logs = session.exec(select(DoseLog).where(DoseLog.user_id == user_id, DoseLog.scheduled_time >= week_ago)).all()

    missed_night = 0
    missed_morning = 0
    late_count = 0
    for l in logs:
        b = _bucket(l.scheduled_time)
        if l.status == DoseStatus.missed and b == "night":
            missed_night += 1
        if l.status == DoseStatus.missed and b == "morning":
            missed_morning += 1
        if l.status == DoseStatus.late:
            late_count += 1

    if missed_night >= 3:
        return AiSuggestionOut(suggestion="You often miss your night dose. Try moving the reminder 30 minutes earlier (e.g. 8:30 PM).")
    if missed_morning >= 3:
        return AiSuggestionOut(suggestion="Mornings look tough lately. Try a slightly later reminder time (e.g. 30 minutes later).")
    if late_count >= 5:
        return AiSuggestionOut(suggestion="You’re frequently taking doses late. Consider a larger reminder window or an earlier first alert.")
    return AiSuggestionOut(suggestion="Nice work staying consistent. Keep the same schedule this week.")


@app.post("/caregiver/alert")
def caregiver_alert(
    payload: CaregiverAlertIn,
    auth_user: AuthUser = Depends(get_current_auth_user),
    session: Session = Depends(get_session),
):
    # MVP: store-only behavior can be added later. For now just accept.
    return {"queued": True, "user_id": payload.user_id, "medication_id": payload.medication_id, "level": payload.alert_level}


@app.post("/scan-medication", response_model=ScanMedicationOut)
async def scan_medication(payload: ScanMedicationIn):
    """
    LLM-backed extraction from OCR text → {name,dosage,instructions,frequency_per_day,recommended_times_minutes}.
    Falls back to a tiny heuristic if OPENAI_API_KEY isn't configured.
    """
    text = payload.text.strip()
    if not text:
        return ScanMedicationOut(
            name="",
            dosage="",
            instructions="",
            frequency_per_day=0,
            recommended_times_minutes=[],
        )

    # Debug/testing override: force the medication name deterministically.
    forced_name, forced_dosage, forced_instructions = _scan_medication_forced_overrides()
    if forced_name or forced_dosage or forced_instructions:
        return ScanMedicationOut(
            name=forced_name,
            dosage=forced_dosage,
            instructions=forced_instructions,
            frequency_per_day=0,
            recommended_times_minutes=[],
        )

    if not (settings.openai_api_key or "").strip():
        # Fallback: return best-effort *non-placeholder* values.
        # (Client-side local parsing already handles "see label" style UX.)
        name = text.splitlines()[0][:40] if text else "Medication"
        dosage = ""
        instructions = ""
        return ScanMedicationOut(
            name=name,
            dosage=dosage,
            instructions=instructions,
            frequency_per_day=0,
            recommended_times_minutes=[],
        )

    # Lightweight hints help the model avoid picking the wrong line from noisy OCR.
    hints = _ocr_hints(text)
    hints_block = "\n".join(f"- {k}: {v}" for k, v in hints.items() if v)
    if not hints_block:
        hints_block = "- (none)"

    system = (
        "You extract structured medication info from messy OCR of prescription labels.\n"
        "Rules:\n"
        "- Output must match the provided JSON schema (no extra keys).\n"
        "- Use empty string when unknown.\n"
        "- Use 0 / [] when unknown for numeric/list fields.\n"
        "- IMPORTANT: map OCR into fields like this:\n"
        "  - name: the drug name line ONLY (e.g. 'bromphen-PSE-DM') and nothing about dose or directions.\n"
        "  - dosage: the label strength/concentration line ONLY (e.g. '2-30-10 mg/5 mL' or '500 mg tablet').\n"
        "    If both a concentration line (mg/5mL) and a 'Take 10 mL' dose-amount line exist, dosage should be the concentration line.\n"
        "  - instructions: the route + cadence ONLY (e.g. 'by mouth every 6 hours', 'swallow', 'take by mouth').\n"
        "    Do NOT include the numeric strength (mL/mg) in instructions if it is already captured in dosage.\n"
        "- name: copy the ENTIRE LINE that states the medication/drug name (do not truncate),\n"
        "  but still exclude obvious non-drug lines like patient/pharmacy/address/doctor/Rx#.\n"
        "- IMPORTANT name heuristic: prescription labels often contain dash-separated abbreviated chemical/drug names.\n"
        "  If you see a line with multiple uppercase segments separated by dashes (e.g. 'ABCD-EFGH' or 'FOO-BAR-BAZ'),\n"
        "  that is a VERY strong candidate for the medication name.\n"
        "  Keep the ENTIRE dash-separated phrase (do not truncate to a single segment), because it may represent multiple combined chemicals.\n"
        "  Prefer that over addresses, phone numbers, patient names, or IDs.\n"
        "- dosage: usually appears as a number + unit inside the description (e.g. '5 mg', '10 mL', '250 mcg').\n"
        "  Return the strength (and form if present) but do not return vague text.\n"
        "- instructions: should read like 'take by mouth', 'swallow', 'liquid to swallow', etc.\n"
        "  Instructions usually do NOT contain numbers; if you only find numbered SIG text, prefer the non-number wording if present.\n"
        "  If the OCR contains an interval like 'every 6 hours', include that phrase in instructions.\n"
        "- frequency_per_day: integer number of times per day (1..12), or 0 if unknown.\n"
        "- recommended_times_minutes: list of minutes since midnight (0..1439), length should match frequency_per_day when possible.\n"
        "  If the label says 'twice daily' and no times are provided, choose reasonable defaults like [540, 1260] (9:00, 21:00).\n"
        "  If the label is interval-based (e.g. 'every 6 hours') and no start time is provided, you may set frequency_per_day but return recommended_times_minutes as [].\n"
        "- NEVER output placeholder dosage/instructions like 'see label', 'refer to label', 'see bottle', 'take as directed'. If unknown, return empty string.\n"
        "- Never invent details not supported by the OCR."
    )

    user = (
        "OCR text (noisy):\n"
        f"{text}\n\n"
        "Heuristic hints (may be wrong):\n"
        f"{hints_block}\n"
    )

    schema = {
        "type": "object",
        "properties": {
            "name": {"type": "string"},
            "dosage": {"type": "string"},
            "instructions": {"type": "string"},
            "frequency_per_day": {"type": "integer"},
            "recommended_times_minutes": {
                "type": "array",
                "items": {"type": "integer"},
            },
        },
        "required": [
            "name",
            "dosage",
            "instructions",
            "frequency_per_day",
            "recommended_times_minutes",
        ],
        "additionalProperties": False,
    }

    payload_json = {
        "model": settings.openai_model,
        "input": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": 0.0,
        # Responses API structured outputs.
        "text": {
            "format": {
                "type": "json_schema",
                "name": "scan_medication",
                "strict": True,
                "schema": schema,
            }
        },
    }

    try:
        async with httpx.AsyncClient(timeout=40.0) as client:
            r = await client.post(
                "https://api.openai.com/v1/responses",
                headers={
                    "Authorization": f"Bearer {settings.openai_api_key}",
                    "Content-Type": "application/json",
                },
                json=payload_json,
            )
        r.raise_for_status()
        data = r.json()
        content = _openai_response_text(data)
        parsed = _try_parse_json_object(content) or {}
        freq = parsed.get("frequency_per_day")
        if not isinstance(freq, int):
            try:
                freq = int(freq)
            except Exception:
                freq = 0

        rec_times = parsed.get("recommended_times_minutes") or []
        cleaned_times = []
        if isinstance(rec_times, list):
            for t in rec_times:
                try:
                    m = int(t)
                except Exception:
                    continue
                if 0 <= m < 24 * 60:
                    cleaned_times.append(m)
        cleaned_times = sorted(list(dict.fromkeys(cleaned_times)))

        name_out = str(parsed.get("name") or "").strip()
        dosage_out = str(parsed.get("dosage") or "").strip()
        instr_out = str(parsed.get("instructions") or "").strip()

        # Normalization: remove common cross-contamination between fields.
        strength_unit_re = re.compile(r"\b\d+(?:\.\d+)?\s*(mg|mcg|g|ml|units?)\b", flags=re.I)
        take_words_re = re.compile(r"\b(take|by mouth|mouth|swallow|liquid)\b", flags=re.I)

        # If the model accidentally included strength in the name line, remove it.
        if name_out:
            name_out = strength_unit_re.sub("", name_out).strip(" -,:;")

        # If dosage includes direction words, strip down to the first strength+unit (and optional form token).
        if dosage_out and take_words_re.search(dosage_out):
            m = strength_unit_re.search(dosage_out)
            if m:
                dosage_out = m.group(0).strip()

        # If instructions includes strength (e.g. "Take 10 mL by mouth ..."), remove the strength portion.
        if instr_out:
            instr_out = strength_unit_re.sub("", instr_out).replace("  ", " ").strip(" -,:;")

        # Guardrail: never return "see label/bottle" placeholders; prefer empty so client fallback can fill.
        _placeholder_re = re.compile(
            r"\b("
            r"see\s*(the\s*)?(label|bottle)|refer\s*to\s*(the\s*)?label|"
            r"as\s*directed|take\s*as\s*directed|"
            r"see\s*instructions|see\s*label\s*for\s*instructions"
            r")\b",
            flags=re.I,
        )
        if dosage_out and _placeholder_re.search(dosage_out):
            dosage_out = ""
        if instr_out and _placeholder_re.search(instr_out):
            instr_out = ""

        # Prefer the concentration/strength line for dosage when present (e.g. "2-30-10 mg/5 mL").
        concentration_guess = str(hints.get("concentration_guess") or "").strip()
        if concentration_guess:
            dosage_out = concentration_guess

        # Guardrail: if we detected a dash-name candidate line and the model returned only a substring,
        # prefer the entire original line (user requirement).
        dash_line = str(hints.get("dash_name_candidate") or "").strip()
        if dash_line and name_out and name_out.lower() in dash_line.lower() and len(dash_line) > len(name_out):
            name_out = dash_line

        # Guardrail: dosage should usually include a numeric strength + unit (mg/mcg/g/mL/units).
        # If the model returned non-empty dosage but no unit/strength, prefer OCR-derived strength if present.
        if dosage_out and not re.search(r"\b\d+(?:\.\d+)?\s*(mg|mcg|g|ml|units?)\b", dosage_out, flags=re.I):
            strength_guess = str(hints.get("dosage_guess") or "").strip()
            if strength_guess:
                dosage_out = strength_guess

        # Guardrail: if the label clearly contains mL but the model picked mg, prefer the OCR strength_guess.
        if dosage_out and re.search(r"\bmg\b", dosage_out, flags=re.I) and re.search(r"\bml\b", text, flags=re.I):
            strength_guess = str(hints.get("dosage_guess") or "").strip()
            if strength_guess and re.search(r"\bml\b", strength_guess, flags=re.I):
                dosage_out = strength_guess

        # Guardrail: instructions usually shouldn't be mostly numeric; if we have a cleaner OCR hint, prefer it.
        if instr_out and re.search(r"\d", instr_out):
            instr_guess = str(hints.get("instructions_guess") or "").strip()
            if instr_guess and not re.search(r"\d", instr_guess):
                instr_out = instr_guess

        # Guardrail: if we detected an "every X hours" interval and instructions don't mention it, add it.
        try:
            interval_hours = int(hints.get("interval_hours") or 0)
        except Exception:
            interval_hours = 0
        if interval_hours > 0 and (not re.search(r"\bevery\b", instr_out, flags=re.I)):
            suffix = f"every {interval_hours} hours"
            instr_out = (instr_out.strip() + (" " if instr_out.strip() else "") + suffix).strip()

        # If interval-based and frequency_per_day looks unknown, derive it.
        if interval_hours > 0 and int(freq or 0) == 0:
            try:
                freq = max(1, min(12, int(round(24 / interval_hours))))
            except Exception:
                freq = 0

        return ScanMedicationOut(
            name=name_out,
            dosage=dosage_out,
            instructions=instr_out,
            frequency_per_day=max(0, int(freq)),
            recommended_times_minutes=cleaned_times,
        )
    except Exception:
        log.exception("scan_medication: OpenAI call failed; falling back")
        name = text.splitlines()[0][:40] if text else "Medication"
        dosage = ""
        instructions = ""
        return ScanMedicationOut(
            name=name,
            dosage=dosage,
            instructions=instructions,
            frequency_per_day=0,
            recommended_times_minutes=[],
        )


def _ocr_hints(text: str) -> dict:
    """
    Best-effort guesses to guide the LLM on noisy OCR.
    Keep this conservative: return empty strings when unsure.
    """
    t = (text or "").strip()
    if not t:
        return {
            "name_guess": "",
            "dash_name_candidate": "",
            "dosage_guess": "",
            "instructions_guess": "",
            "dose_amount_guess": "",
            "concentration_guess": "",
            "interval_hours": 0,
        }

    lines = [ln.strip() for ln in re.split(r"\r?\n", t) if ln.strip()]
    lower_lines = [ln.lower() for ln in lines]

    # Dosage strength/form guess.
    strength = ""
    m = re.search(r"\b\d+(?:\.\d+)?\s*(mg|mcg|g|ml|units?)\b", t, flags=re.I)
    if m:
        strength = m.group(0).strip()

    form = ""
    for candidate in ("tablet", "tab", "capsule", "cap", "solution", "suspension", "cream", "ointment", "spray", "inhaler", "patch", "drops"):
        if re.search(rf"\b{re.escape(candidate)}s?\b", t, flags=re.I):
            form = candidate
            break

    dosage_guess = " ".join(x for x in [strength, form] if x).strip()

    # Instructions guess: pick the first line that looks like a SIG.
    instructions_guess = ""
    sig_markers = ("take", "by mouth", "mouth", "daily", "twice", "once", "every", "at bedtime", "with food", "before meals", "after meals", "as needed", "prn", "apply", "inhale", "instill")
    for ln, lln in zip(lines, lower_lines):
        if any(mk in lln for mk in sig_markers) and len(ln) >= 8:
            instructions_guess = ln
            break

    # Dose amount guess: often "Take 10 mL ..." on liquid labels.
    dose_amount_guess = ""
    m_dose = re.search(r"\btake\s+(\d+(?:\.\d+)?)\s*(ml|mL)\b", t, flags=re.I)
    if m_dose:
        dose_amount_guess = f"{m_dose.group(1)} mL"

    # Concentration/strength line guess, e.g. "2-30-10 MG/5ML" or "10 mg/5 mL".
    concentration_guess = ""
    m_conc = re.search(
        r"\b(\d+(?:-\d+){1,3})\s*(mg|mcg|g)\s*/\s*(\d+(?:\.\d+)?)\s*(ml|mL)\b",
        t,
        flags=re.I,
    )
    if m_conc:
        # Preserve the original matched string with normalized spacing/case.
        concentration_guess = f"{m_conc.group(1)} mg/{m_conc.group(3)} mL"

    # Interval hint: capture "every X hours" patterns for scheduling.
    interval_hours = 0
    m_int = re.search(r"\bevery\s+(\d{1,2})\s*(hours?|hrs?|hr|h)\b", t, flags=re.I)
    if m_int:
        try:
            interval_hours = int(m_int.group(1))
        except Exception:
            interval_hours = 0

    # Dash-separated uppercase chemical/drug string candidate.
    # Keep the ENTIRE line (not just the token), per app UX needs.
    dash_name_candidate = ""
    # Allow mixed case because OCR often returns e.g. "bromphen-PSE-DM".
    dash_re = re.compile(r"\b[A-Za-z0-9]{2,}(?:-[A-Za-z0-9]{1,})+\b")
    for ln in lines:
        if dash_re.search(ln):
            dash_name_candidate = ln
            break

    # Name guess: prefer first short-ish non-junk line that isn't obviously demographic/pharmacy.
    name_guess = ""
    junk_markers = ("patient", "address", "rx", "refill", "pharmacy", "doctor", "dr.", "qty", "date", "phone", "take", "sig", "directions")
    for ln, lln in zip(lines, lower_lines):
        if any(j in lln for j in junk_markers):
            continue
        if re.search(r"\b\d{2,}\b", ln):  # avoid lines dominated by ids
            continue
        if 2 <= len(ln) <= 50:
            name_guess = ln
            break

    return {
        "name_guess": name_guess,
        "dash_name_candidate": dash_name_candidate,
        "dosage_guess": dosage_guess,
        "instructions_guess": instructions_guess,
        "dose_amount_guess": dose_amount_guess,
        "concentration_guess": concentration_guess,
        "interval_hours": interval_hours,
    }


def _openai_response_text(resp: dict) -> str:
    """
    Best-effort extraction of text from the Responses API JSON.
    """
    # Preferred: output_text convenience field (present in many SDK/HTTP responses).
    t = resp.get("output_text")
    if isinstance(t, str) and t.strip():
        return t.strip()

    # Otherwise: stitch together output[].content[].text.
    out = resp.get("output")
    if isinstance(out, list):
        parts: list[str] = []
        for item in out:
            if not isinstance(item, dict):
                continue
            content = item.get("content")
            if not isinstance(content, list):
                continue
            for c in content:
                if not isinstance(c, dict):
                    continue
                if c.get("type") == "output_text" and isinstance(c.get("text"), str):
                    parts.append(c["text"])
        joined = "\n".join(p.strip() for p in parts if p.strip())
        if joined.strip():
            return joined.strip()

    # Last resort: serialize and hope the client-side wrapper finds JSON somewhere.
    try:
        return json.dumps(resp)
    except Exception:
        return str(resp)


def _try_parse_json_object(s: str) -> dict | None:
    s = (s or "").strip()
    if not s:
        return None
    try:
        d = json.loads(s)
        if isinstance(d, dict):
            return d
    except Exception:
        pass
    start = s.find("{")
    end = s.rfind("}")
    if start < 0 or end <= start:
        return None
    candidate = s[start : end + 1]
    try:
        d = json.loads(candidate)
        if isinstance(d, dict):
            return d
    except Exception:
        return None
    return None

