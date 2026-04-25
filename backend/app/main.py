from __future__ import annotations

import json
import random
import string
from datetime import datetime, timedelta, timezone
from typing import List

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
    LinkCaregiverIn,
    PushTokenIn,
    PushTokenOut,
    DevPushIn,
)
from .settings import settings
from .push.fcm import send_to_token

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


@app.get("/health")
def health():
    return {"ok": True}


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
    token = create_access_token(subject=str(auth_user.id), expires_minutes=settings.access_token_exp_minutes)
    return TokenOut(access_token=token)


@app.post("/auth/login", response_model=TokenOut)
def login(payload: LoginIn, session: Session = Depends(get_session)):
    auth_user = get_auth_user_by_email(session, payload.email)
    if not auth_user or not verify_password(payload.password, auth_user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password.")
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
def scan_medication(
    payload: ScanMedicationIn,
):
    # MVP "mock OCR": naive keyword extraction
    text = payload.text.strip()
    name = "Medication"
    dosage = "1 pill"
    instructions = "Take as directed."
    if "mg" in text.lower():
        dosage = "See label (mg detected)"
    if len(text) > 0:
        name = text.splitlines()[0][:40]
    return ScanMedicationOut(name=name, dosage=dosage, instructions=instructions)

