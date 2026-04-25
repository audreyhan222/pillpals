from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import List, Optional

from sqlmodel import Field, SQLModel


class Role(str, Enum):
    elderly = "elderly"
    caregiver = "caregiver"


class DoseStatus(str, Enum):
    taken = "taken"
    late = "late"
    missed = "missed"


class AlertLevel(int, Enum):
    normal = 1
    loud = 2
    caregiver = 3


class AuthUser(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    email: str = Field(index=True, unique=True)
    password_hash: str
    created_at: datetime = Field(default_factory=datetime.utcnow)


class User(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    auth_user_id: int = Field(index=True)

    name: str
    age: int
    phone: str
    role: Role = Field(index=True)
    caregiver_id: Optional[int] = Field(default=None, index=True)
    emergency_info: Optional[str] = None

    invite_code: str = Field(index=True)


class Caregiver(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    auth_user_id: int = Field(index=True)

    name: str
    phone: str
    relationship: str


class Medication(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(index=True)

    name: str
    dosage: str
    instructions: str
    pill_type: str
    scheduled_times_json: str  # JSON array of "HH:MM"
    reminder_window_minutes: int = 30
    created_at: datetime = Field(default_factory=datetime.utcnow)


class DoseLog(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    medication_id: int = Field(index=True)
    user_id: int = Field(index=True)

    scheduled_time: datetime
    taken_time: Optional[datetime] = None
    status: DoseStatus = Field(index=True)


class Alert(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(index=True)
    medication_id: int = Field(index=True)
    alert_level: AlertLevel = Field(index=True)
    sent_to_caregiver: bool = False
    timestamp: datetime = Field(default_factory=datetime.utcnow)

