from __future__ import annotations

import json
import logging
import random
import re
import string
from datetime import datetime, timedelta, timezone
from typing import List

import httpx
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
    LLM-backed extraction from OCR text → {name,dosage,instructions}.
    Falls back to a tiny heuristic if OPENAI_API_KEY isn't configured.
    """
    text = payload.text.strip()
    if not text:
        return ScanMedicationOut(name="", dosage="", instructions="")

    if not (settings.openai_api_key or "").strip():
        # Fallback: keep previous mock-ish behavior (better than throwing).
        name = text.splitlines()[0][:40] if text else "Medication"
        dosage = "See label" if "mg" in text.lower() else "1 pill"
        instructions = "Take as directed."
        return ScanMedicationOut(name=name, dosage=dosage, instructions=instructions)

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
        "- name: medication name only (exclude patient/pharmacy/address/doctor/Rx#).\n"
        "- dosage: include strength + form if present (e.g. '500 mg tablet', '10 mL', '2 puffs').\n"
        "- instructions: the SIG / directions for use (e.g. 'Take 1 tablet by mouth twice daily with food').\n"
        "- If multiple candidates exist, choose the most medication-like.\n"
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
        },
        "required": ["name", "dosage", "instructions"],
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
        return ScanMedicationOut(
            name=str(parsed.get("name") or "").strip(),
            dosage=str(parsed.get("dosage") or "").strip(),
            instructions=str(parsed.get("instructions") or "").strip(),
        )
    except Exception:
        log.exception("scan_medication: OpenAI call failed; falling back")
        name = text.splitlines()[0][:40] if text else "Medication"
        dosage = "See label" if "mg" in text.lower() else "1 pill"
        instructions = "Take as directed."
        return ScanMedicationOut(name=name, dosage=dosage, instructions=instructions)


def _ocr_hints(text: str) -> dict:
    """
    Best-effort guesses to guide the LLM on noisy OCR.
    Keep this conservative: return empty strings when unsure.
    """
    t = (text or "").strip()
    if not t:
        return {"name_guess": "", "dosage_guess": "", "instructions_guess": ""}

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
        "dosage_guess": dosage_guess,
        "instructions_guess": instructions_guess,
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

