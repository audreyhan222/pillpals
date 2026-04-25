from __future__ import annotations

from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, EmailStr, Field

from .models import DoseStatus, Role


class SignupIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6)


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


class ProfileUpsertIn(BaseModel):
    name: str
    age: int
    phone: str
    role: Role
    emergency_info: Optional[str] = None


class UserOut(BaseModel):
    id: int
    name: str
    age: int
    phone: str
    role: Role
    caregiver_id: Optional[int]
    emergency_info: Optional[str]
    invite_code: str


class CaregiverProfileIn(BaseModel):
    name: str
    phone: str
    relationship: str


class CaregiverOut(BaseModel):
    id: int
    name: str
    phone: str
    relationship: str


class LinkCaregiverIn(BaseModel):
    invite_code: str


class MedicationCreateIn(BaseModel):
    user_id: int
    name: str
    dosage: str
    instructions: str
    pill_type: str
    scheduled_times: List[str]  # "HH:MM"
    reminder_window_minutes: int = 30


class MedicationOut(BaseModel):
    id: int
    user_id: int
    name: str
    dosage: str
    instructions: str
    pill_type: str
    scheduled_times: List[str]
    reminder_window_minutes: int


class DoseConfirmIn(BaseModel):
    medication_id: int
    user_id: int
    scheduled_time: datetime
    taken_time: Optional[datetime] = None


class DoseLogOut(BaseModel):
    id: int
    medication_id: int
    user_id: int
    scheduled_time: datetime
    taken_time: Optional[datetime]
    status: DoseStatus


class InsightOut(BaseModel):
    weekly_adherence_percent: float
    total_taken: int
    total_missed: int
    most_missed_time_bucket: Optional[str]
    morning_vs_night: dict
    current_streak_days: int


class AiSuggestionOut(BaseModel):
    suggestion: str


class CaregiverAlertIn(BaseModel):
    user_id: int
    medication_id: int
    alert_level: int
    message: Optional[str] = None


class ScanMedicationIn(BaseModel):
    text: str


class ScanMedicationOut(BaseModel):
    name: str
    dosage: str
    instructions: str


class PushTokenIn(BaseModel):
    token: str
    platform: str = "ios"


class PushTokenOut(BaseModel):
    ok: bool = True


class DevPushIn(BaseModel):
    title: str = "PillPal (Dev)"
    body: str = "This is a dev-triggered push notification."
    data: Optional[dict] = None

