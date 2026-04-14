from fastapi import FastAPI, APIRouter, HTTPException, Depends, status, UploadFile, File, Body, Query
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from dotenv import load_dotenv
from starlette.middleware.cors import CORSMiddleware
from starlette.concurrency import run_in_threadpool
import os
import logging
import base64
import json
import requests
from pathlib import Path
from pydantic import BaseModel, Field, ConfigDict, EmailStr
from typing import List, Optional, AsyncGenerator
from contextlib import asynccontextmanager
import uuid
import secrets
import hashlib
from datetime import datetime, timezone, timedelta
import jwt
from passlib.context import CryptContext

ROOT_DIR = Path(__file__).parent
load_dotenv(ROOT_DIR / '.env')

# Supabase only
try:
    from . import supabase_client
except Exception:
    import supabase_client

# JWT settings
SECRET_KEY = os.environ.get('JWT_SECRET', 'epilogue-secret-key-change-in-production')
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_DAYS = 7

security = HTTPBearer(auto_error=False)
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

@asynccontextmanager
async def lifespan(app: FastAPI):
    yield

app = FastAPI(lifespan=lifespan)
# Configure CORS early so all routes include Access-Control-Allow-* headers.
# Default to the frontend dev server origin but allow overriding with CORS_ORIGINS env var.
cors_origins = os.environ.get('CORS_ORIGINS', 'http://localhost:3000,http://127.0.0.1:3000')
allow_origins = [o.strip() for o in cors_origins.split(',') if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Ensure CORS headers are present even on unhandled exceptions or 500 responses
@app.middleware("http")
async def ensure_cors_on_error(request, call_next):
    from starlette.responses import PlainTextResponse
    try:
        response = await call_next(request)
    except Exception:
        # Return a generic 500 with CORS headers set below
        response = PlainTextResponse("Internal Server Error", status_code=500)

    origin = request.headers.get("origin")
    if origin and origin in allow_origins:
        response.headers.setdefault("Access-Control-Allow-Origin", origin)
        response.headers.setdefault("Access-Control-Allow-Credentials", "true")

    return response


@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    # Log full traceback for debugging
    logging.exception("Unhandled exception in request")
    from starlette.responses import JSONResponse
    body = {"detail": "Internal Server Error"}
    headers = {}
    origin = request.headers.get("origin")
    if origin and origin in allow_origins:
        headers['Access-Control-Allow-Origin'] = origin
        headers['Access-Control-Allow-Credentials'] = "true"
    return JSONResponse(status_code=500, content=body, headers=headers)

api_router = APIRouter(prefix="/api")

# ============ MODELS ============

# Care Team & Members
class CareTeamCreate(BaseModel):
    patient_first_name: str
    primary_caregiver_name: str
    primary_caregiver_email: EmailStr
    hospice_name: Optional[str] = None
    hospice_org_id: Optional[str] = None
    nurse_line_number: Optional[str] = None

class CareTeam(BaseModel):
    model_config = ConfigDict(extra="ignore")
    id: str
    patient_first_name: str
    hospice_org_id: Optional[str] = None
    nurse_line_number: Optional[str] = None
    created_at: str

class MemberCreate(BaseModel):
    name: str
    email: EmailStr
    role: str  # primary, secondary, remote, professional

class MagicLinkAuth(BaseModel):
    token: str
    pin: Optional[str] = None

class SetPin(BaseModel):
    pin: str

class Member(BaseModel):
    model_config = ConfigDict(extra="ignore")
    id: str
    care_team_id: str
    name: str
    email: str
    role: str
    is_admin: bool = False
    magic_link_token: Optional[str] = None
    access_pin: Optional[str] = None
    joined_at: str
    last_active: Optional[str] = None

# Medications
class MedicationCreate(BaseModel):
    name: str
    strength: str
    typical_dose: str
    route: str
    pattern: str  # scheduled or prn
    schedule_details: Optional[str] = None
    prn_reason_tags: Optional[List[str]] = None
    notes: Optional[str] = None
    deprescribed_at: Optional[str] = None

class Medication(BaseModel):
    model_config = ConfigDict(extra="ignore")
    id: str
    care_team_id: str
    name: str
    strength: str
    typical_dose: str
    route: str
    pattern: str
    schedule_details: Optional[str] = None
    prn_reason_tags: Optional[List[str]] = None
    notes: Optional[str] = None
    deprescribed_at: Optional[str] = None
    created_at: str
    created_by_member_id: str

class MedicationImageExtraction(BaseModel):
    """Structured response from backend image extraction.

    Matches the keys expected by the Flutter UI and keeps all fields optional
    so the UI can fall back to manual edits when extraction is incomplete.
    """

    name: Optional[str] = None
    dosage_amount: Optional[str] = None
    dosage_unit: Optional[str] = None
    route: Optional[str] = None
    is_prn: Optional[bool] = None
    frequency: Optional[str] = None
    prescribed_date: Optional[str] = None
    instructions: Optional[str] = None


def _extract_json_object(raw: str) -> str:
    cleaned = (raw or "").strip()
    cleaned = cleaned.replace("```json", "").replace("```", "").strip()
    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError("Could not find JSON object in Gemini response")
    return cleaned[start : end + 1]


def _gemini_extract_medication(image_bytes: bytes, mime_type: str) -> MedicationImageExtraction:
    api_key = (os.environ.get("GEMINI_API_KEY") or "").strip()
    if not api_key:
        raise RuntimeError("Missing GEMINI_API_KEY in backend environment")

    schema_hint = (
        '{'
        '"name": string|null,'
        '"dosage_amount": string|null,'
        '"dosage_unit": "mg"|"mcg"|"mL"|"tabs"|"caps"|"drops"|null,'
        '"route": "By mouth"|"Sublingual"|"Topical"|"Injection"|"Suppository"|"Inhaled"|"Other"|null,'
        '"is_prn": boolean|null,'
        '"frequency": string|null,'
        '"prescribed_date": string|null,'
        '"instructions": string|null'
        '}'
    )

    prompt = (
        "You are given a photo of a medication box/strip/bottle label or a prescription.\n"
        "Extract medication details and return ONLY a single JSON object (no markdown, no code fences).\n"
        "Use this exact schema and key names: "
        + schema_hint
        + "\nRules:\n"
        "- If a value is not present or you are unsure, set it to null.\n"
        "- Use dosage_unit from the allowed set in the schema.\n"
        "- Use route from the allowed set in the schema.\n"
        "- For prescribed_date: if you can identify a date, return ISO-8601 date-time string; otherwise null.\n"
        "- frequency can be plain text as seen (e.g., \"Once daily\", \"Twice daily\", \"Every 6 hours\", \"As needed\").\n"
        "- instructions: include directions like \"take with food\" if present."
    )

    # NOTE: Some projects no longer expose gemini-1.5-flash via ListModels.
    # Prefer a current Flash model and fall back gracefully.
    model_candidates = [
        "gemini-1.5-flash",  # legacy
        "gemini-flash-latest",
        "gemini-2.0-flash",
        "gemini-2.5-flash",
    ]

    payload = {
        "contents": [
            {
                "parts": [
                    {"text": prompt},
                    {
                        "inline_data": {
                            "mime_type": mime_type or "image/jpeg",
                            "data": base64.b64encode(image_bytes).decode("utf-8"),
                        }
                    },
                ]
            }
        ],
        "generationConfig": {
            "temperature": 0.2,
            "topP": 0.9,
            "maxOutputTokens": 512,
        },
    }

    last_error = None
    resp = None
    for model_name in model_candidates:
        endpoint = (
            "https://generativelanguage.googleapis.com/v1beta/models/"
            + model_name
            + ":generateContent?key="
            + api_key
        )

        resp = requests.post(endpoint, json=payload, timeout=60)
        if resp.status_code < 400:
            break

        # If model isn't available, try the next candidate.
        if resp.status_code in (404,):
            last_error = f"{model_name}: {resp.status_code}"
            continue

        # For other errors (auth/quota/etc), fail fast.
        raise RuntimeError(f"Gemini request failed: {resp.status_code} {resp.text}")

    if resp is None or resp.status_code >= 400:
        raise RuntimeError(
            f"Gemini request failed: {resp.status_code if resp else 'no_response'} {resp.text if resp else ''} (last_model_error={last_error})"
        )

    data = resp.json()
    candidates = data.get("candidates") or []
    text = ""
    if candidates:
        content = (candidates[0].get("content") or {})
        parts = content.get("parts") or []
        if parts:
            text = (parts[0].get("text") or "").strip()

    if not text:
        raise RuntimeError("Empty response from Gemini")

    json_text = _extract_json_object(text)
    decoded = json.loads(json_text)
    if not isinstance(decoded, dict):
        raise RuntimeError("Gemini response was not a JSON object")

    # Normalize empty strings to null.
    normalized = {}
    for k, v in decoded.items():
        if isinstance(v, str):
            s = v.strip()
            normalized[k] = s if s else None
        else:
            normalized[k] = v

    # Ensure only expected keys are used.
    allowed = {
        "name",
        "dosage_amount",
        "dosage_unit",
        "route",
        "is_prn",
        "frequency",
        "prescribed_date",
        "instructions",
    }
    filtered = {k: normalized.get(k) for k in allowed}

    # Coerce is_prn if Gemini returned string.
    raw_prn = filtered.get("is_prn")
    if isinstance(raw_prn, str):
        low = raw_prn.strip().lower()
        if low in {"true", "yes"}:
            filtered["is_prn"] = True
        elif low in {"false", "no"}:
            filtered["is_prn"] = False
        else:
            filtered["is_prn"] = None

    return MedicationImageExtraction(**filtered)

class DoseLogCreate(BaseModel):
    medication_id: str
    amount_given: str
    who_gave: Optional[str] = None
    note: Optional[str] = None

class DoseLog(BaseModel):
    model_config = ConfigDict(extra="ignore")
    id: str
    care_team_id: str
    medication_id: str
    medication_name: str
    dose_time: str
    amount_given: str
    who_gave: Optional[str] = None
    note: Optional[str] = None
    logged_by_member_id: str
    logged_by_member_name: str
    editable_until: str
    event_id: Optional[str] = None  # Link to symptom event

# Symptom Events & Nurse Contact
class SymptomEventCreate(BaseModel):
    symptoms: List[str]
    severity: str
    what_happened: str

class SymptomEvent(BaseModel):
    model_config = ConfigDict(extra="ignore")
    id: str
    care_team_id: str
    symptoms: List[str]
    severity: str
    what_happened: str
    event_time: str
    created_by_member_id: str
    created_by_member_name: str
    editable_until: str

class SkinWoundEventCreate(BaseModel):
    has_skin_condition: bool = False
    skin_condition: Optional[str] = None
    treatments: List[str] = Field(default_factory=list)
    image_urls: List[str] = Field(default_factory=list)
    notes: Optional[str] = None

class SkinWoundEvent(BaseModel):
    model_config = ConfigDict(extra="ignore")
    id: str
    care_team_id: str
    has_skin_condition: bool = False
    skin_condition: Optional[str] = None
    treatments: List[str] = Field(default_factory=list)
    image_urls: List[str] = Field(default_factory=list)
    notes: Optional[str] = None
    event_time: str
    deleted_at: Optional[str] = None
    created_by_member_id: Optional[str] = None
    created_by_member_name: Optional[str] = None
    editable_until: Optional[str] = None

class NurseContactAttempt(BaseModel):
    model_config = ConfigDict(extra="ignore")
    id: str
    care_team_id: str
    symptom_event_id: Optional[str] = None
    contact_method: str  # sms, call
    status: str  # sent, failed, pending
    message_body: Optional[str] = None
    attempted_at: str
    attempted_by_member_id: str

# Observations (Quick Notes)
class ObservationCreate(BaseModel):
    content: str
    category: Optional[str] = None

class Observation(BaseModel):
    model_config = ConfigDict(extra="ignore")
    id: str
    care_team_id: str
    content: str
    category: Optional[str] = None
    created_at: str
    created_by_member_id: str
    created_by_member_name: str

# Moments
class MomentCreate(BaseModel):
    category: str  # they_love, it_comforts, good_moment
    content: str
    visibility: str  # care_team or private
    photo_url: Optional[str] = None

class Moment(BaseModel):
    model_config = ConfigDict(extra="ignore")
    id: str
    care_team_id: str
    category: str
    content: str
    visibility: str
    photo_url: Optional[str] = None
    created_at: str
    created_by_member_id: str
    created_by_member_name: str

# Care Plan & Routines
class CarePlanUpdate(BaseModel):
    medications_summary: Optional[str] = None
    positioning_turning: Optional[str] = None
    transfers: Optional[str] = None
    mobility: Optional[str] = None
    personal_care: Optional[str] = None
    other_instructions: Optional[str] = None
    hospice_instructions: Optional[str] = None

class CarePlan(BaseModel):
    model_config = ConfigDict(extra="ignore")
    care_team_id: str
    medications_summary: Optional[str] = None
    positioning_turning: Optional[str] = None
    transfers: Optional[str] = None
    mobility: Optional[str] = None
    personal_care: Optional[str] = None
    other_instructions: Optional[str] = None
    hospice_instructions: Optional[str] = None
    updated_at: str
    updated_by_member_id: str

# Calendar Events
class CalendarEventCreate(BaseModel):
    event_type: str  # hospice_visit, equipment, agency_shift
    title: str
    date: str
    time_window_start: Optional[str] = None
    time_window_end: Optional[str] = None
    visitor_role: Optional[str] = None
    notes: Optional[str] = None

class CalendarEvent(BaseModel):
    model_config = ConfigDict(extra="ignore")
    id: str
    care_team_id: str
    event_type: str
    title: str
    date: str
    time_window_start: Optional[str] = None
    time_window_end: Optional[str] = None
    visitor_role: Optional[str] = None
    notes: Optional[str] = None
    created_at: str
    created_by_member_id: str

# Daily Check-ins
class CheckInResponse(BaseModel):
    question_id: str
    response: str

class CheckIn(BaseModel):
    model_config = ConfigDict(extra="ignore")
    id: str
    care_team_id: str
    member_id: str
    question_text: str
    response: str
    created_at: str

# Professional Caregiver Shift Notes
class ShiftNoteCreate(BaseModel):
    shift_date: str
    arrived_at: Optional[str] = None
    left_at: Optional[str] = None
    tasks_completed: List[str]
    what_i_noticed: str
    flag_for_primary_only: bool = False

class ShiftNote(BaseModel):
    model_config = ConfigDict(extra="ignore")
    id: str
    care_team_id: str
    member_id: str
    member_name: str
    shift_date: str
    arrived_at: Optional[str] = None
    left_at: Optional[str] = None
    tasks_completed: List[str]
    what_i_noticed: str
    flag_for_primary_only: bool
    created_at: str

# ============ HELPER FUNCTIONS ============

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": int(expire.timestamp())})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

def verify_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Session expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid session")

def hash_pin(pin: str) -> str:
    return pwd_context.hash(pin)

def verify_pin(pin: str, stored_hash: str) -> bool:
    # Support legacy SHA256 pins for migration
    if stored_hash.startswith("$2"):
        return pwd_context.verify(pin, stored_hash)
    legacy_hash = hashlib.sha256(pin.encode()).hexdigest()
    return secrets.compare_digest(legacy_hash, stored_hash)

def _sb_raise(res):
    err = getattr(res, "error", None)
    if err:
        raise HTTPException(status_code=500, detail=str(err))

async def sb_insert(table: str, row: dict):
    res = await run_in_threadpool(supabase_client.insert, table, row)
    _sb_raise(res)
    return res.data or []

async def sb_select(
    table: str,
    query: str = "*",
    eq: Optional[dict] = None,
    limit: Optional[int] = None,
    order: Optional[str] = None,
    desc: bool = False
):
    res = await run_in_threadpool(supabase_client.select, table, query, eq, limit, order, desc)
    _sb_raise(res)
    return res.data or []

async def sb_update(table: str, row: dict, eq: Optional[dict] = None):
    res = await run_in_threadpool(supabase_client.update, table, row, eq)
    _sb_raise(res)
    return res.data or []

async def sb_delete(table: str, eq: dict):
    res = await run_in_threadpool(supabase_client.delete, table, eq)
    _sb_raise(res)
    return res.data or []

async def get_current_member(credentials: HTTPAuthorizationCredentials = Depends(security)):
    if not credentials:
        raise HTTPException(status_code=401, detail="Not authenticated")
    
    token = credentials.credentials
    payload = verify_token(token)
    member_id = payload.get("sub")
    if not member_id:
        raise HTTPException(status_code=401, detail="Invalid session")
    
    members = await sb_select("members", "*", {"id": member_id}, limit=1)
    member = members[0] if members else None
    if not member:
        raise HTTPException(status_code=401, detail="Member not found")

    member.pop("magic_link_token", None)
    member.pop("access_pin", None)
    
    # Update last active
    await sb_update("members", {"last_active": datetime.now(timezone.utc).isoformat()}, {"id": member_id})
    
    return Member(**member)

async def track_analytics_event(event_type: str, care_team_id: str, member_role: str, properties: dict = None):
    """Track analytics events without PII"""
    event_doc = {
        "event_type": event_type,
        "care_team_id": care_team_id,
        "member_role": member_role,
        "properties": properties or {},
        "timestamp": datetime.now(timezone.utc).isoformat()
    }
    await sb_insert("analytics_events", event_doc)

# ============ ENDPOINTS ============

# Onboarding & Auth
@api_router.post("/care-teams")
async def create_care_team(team_data: CareTeamCreate):
    try:
        team_id = str(uuid.uuid4())
        member_id = str(uuid.uuid4())
        magic_token = secrets.token_urlsafe(32)
        hospice_org_id = team_data.hospice_org_id or team_data.hospice_name
        
        team_doc = {
            "id": team_id,
            "patient_first_name": team_data.patient_first_name,
            "hospice_org_id": hospice_org_id,
            "nurse_line_number": team_data.nurse_line_number,
            "created_at": datetime.now(timezone.utc).isoformat()
        }
        await sb_insert("care_teams", team_doc)
        member_doc = {
            "id": member_id,
            "care_team_id": team_id,
            "name": team_data.primary_caregiver_name,
            "email": team_data.primary_caregiver_email,
            "role": "primary",
            "is_admin": True,
            "magic_link_token": magic_token,
            "access_pin": None,
            "joined_at": datetime.now(timezone.utc).isoformat(),
            "last_active": datetime.now(timezone.utc).isoformat()
        }
        await sb_insert("members", member_doc)
        
        # Create default care plan
        care_plan_doc = {
            "care_team_id": team_id,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "updated_by_member_id": member_id
        }
        await sb_insert("care_plans", care_plan_doc)
        
        return {"team_id": team_id, "magic_token": magic_token}
    except HTTPException:
        # Re-raise HTTPException so FastAPI handles it
        raise
    except Exception as e:
        logging.exception("Error creating care team")
        raise HTTPException(status_code=500, detail=str(e))

@api_router.post("/auth/magic-link")
async def auth_with_magic_link(
    auth: Optional[MagicLinkAuth] = Body(None),
    token: Optional[str] = Query(None),
    pin: Optional[str] = Query(None)
):
    token_value = auth.token if auth and auth.token else token
    pin_value = auth.pin if auth else pin
    if not token_value:
        raise HTTPException(status_code=400, detail="Missing token")

    members = await sb_select("members", "*", {"magic_link_token": token_value}, limit=1)
    member = members[0] if members else None
    if not member:
        raise HTTPException(status_code=401, detail="Invalid or expired link")
    
    # Check PIN if set
    if member.get("access_pin"):
        if not pin_value:
            raise HTTPException(status_code=401, detail="PIN required")
        if not verify_pin(pin_value, member["access_pin"]):
            raise HTTPException(status_code=401, detail="Invalid PIN")
        # Upgrade legacy hashes after successful verification
        if not member["access_pin"].startswith("$2"):
            new_hash = hash_pin(pin_value)
            await sb_update("members", {"access_pin": new_hash}, {"id": member["id"]})
    
    access_token = create_access_token({"sub": member["id"]})
    await sb_update("members", {"last_active": datetime.now(timezone.utc).isoformat()}, {"id": member["id"]})
    teams = await sb_select("care_teams", "*", {"id": member["care_team_id"]}, limit=1)
    team = teams[0] if teams else None

    member_safe = dict(member)
    member_safe.pop("magic_link_token", None)
    member_safe.pop("access_pin", None)
    
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "member": Member(**member_safe),
        "care_team": CareTeam(**team) if team else None
    }

@api_router.post("/auth/set-pin")
async def set_access_pin(pin_data: SetPin, current_member: Member = Depends(get_current_member)):
    pin_hash = hash_pin(pin_data.pin)
    await sb_update("members", {"access_pin": pin_hash}, {"id": current_member.id})
    return {"message": "PIN set"}

# Member Management
@api_router.post("/members/invite")
async def invite_member(invite: MemberCreate, current_member: Member = Depends(get_current_member)):
    if current_member.role not in ["primary", "secondary"]:
        raise HTTPException(status_code=403, detail="Only primary/secondary can invite")
    
    magic_token = secrets.token_urlsafe(32)
    member_doc = {
        "id": str(uuid.uuid4()),
        "care_team_id": current_member.care_team_id,
        "name": invite.name,
        "email": invite.email,
        "role": invite.role,
        "is_admin": False,
        "magic_link_token": magic_token,
        "access_pin": None,
        "joined_at": datetime.now(timezone.utc).isoformat()
    }
    await sb_insert("members", member_doc)

    # In production, send email with magic link
    magic_link = f"{os.environ.get('FRONTEND_URL', 'http://localhost:3000')}/join/{magic_token}"

    return {"member_id": member_doc["id"], "magic_link": magic_link}

@api_router.post("/admin/members")
async def admin_add_member(invite: MemberCreate, current_member: Member = Depends(get_current_member)):
    if not current_member.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")
    
    magic_token = secrets.token_urlsafe(32)
    member_doc = {
        "id": str(uuid.uuid4()),
        "care_team_id": current_member.care_team_id,
        "name": invite.name,
        "email": invite.email,
        "role": invite.role,
        "is_admin": False,
        "magic_link_token": magic_token,
        "access_pin": None,
        "joined_at": datetime.now(timezone.utc).isoformat()
    }
    await sb_insert("members", member_doc)
    
    magic_link = f"{os.environ.get('FRONTEND_URL', 'http://localhost:3000')}/join/{magic_token}"
    
    return {"member_id": member_doc["id"], "magic_link": magic_link, "member": Member(**member_doc)}

@api_router.get("/members")
async def get_members(current_member: Member = Depends(get_current_member)):
    members = await sb_select("members", "*", {"care_team_id": current_member.care_team_id}, limit=100)
    for m in members:
        m.pop("magic_link_token", None)
        m.pop("access_pin", None)
    return [Member(**m) for m in members]

@api_router.delete("/members/{member_id}")
async def remove_member(member_id: str, current_member: Member = Depends(get_current_member)):
    if current_member.role != "primary":
        raise HTTPException(status_code=403, detail="Only primary can remove members")
    
    deleted = await sb_delete("members", {"id": member_id, "care_team_id": current_member.care_team_id})
    if not deleted:
        raise HTTPException(status_code=404, detail="Member not found")
    return {"message": "Member removed"}

# Medications
@api_router.post("/medications")
async def create_medication(med: MedicationCreate, current_member: Member = Depends(get_current_member)):
    med_doc = {
        "id": str(uuid.uuid4()),
        "care_team_id": current_member.care_team_id,
        **med.model_dump(),
        "created_at": datetime.now(timezone.utc).isoformat(),
        "created_by_member_id": current_member.id
    }
    await sb_insert("medications", med_doc)
    return Medication(**med_doc)

@api_router.get("/medications")
async def get_medications(current_member: Member = Depends(get_current_member)):
    meds = await sb_select("medications", "*", {"care_team_id": current_member.care_team_id}, limit=1000)
    return [Medication(**m) for m in meds]


@api_router.post("/medications/extract")
async def extract_medication_from_image(
    image: UploadFile = File(...),
):
    """Backend-only Gemini extraction.

    This endpoint intentionally returns only structured extraction fields.
    The mobile app can still show a confirmation UI and then persist using
    its existing Supabase schema-aware logic.
    """

    try:
        content_type = (image.content_type or "image/jpeg").strip() or "image/jpeg"
        image_bytes = await image.read()
        if not image_bytes:
            raise HTTPException(status_code=400, detail="Empty image")

        extraction = await run_in_threadpool(
            _gemini_extract_medication,
            image_bytes,
            content_type,
        )
        return extraction.model_dump()
    except HTTPException:
        raise
    except Exception as e:
        logging.exception("Medication image extraction failed")
        raise HTTPException(status_code=500, detail=str(e))

@api_router.post("/dose-logs")
async def log_dose(dose: DoseLogCreate, current_member: Member = Depends(get_current_member)):
    meds = await sb_select("medications", "*", {"id": dose.medication_id, "care_team_id": current_member.care_team_id}, limit=1)
    med = meds[0] if meds else None
    if not med:
        raise HTTPException(status_code=404, detail="Medication not found")
    
    now = datetime.now(timezone.utc)
    dose_doc = {
        "id": str(uuid.uuid4()),
        "care_team_id": current_member.care_team_id,
        "medication_id": dose.medication_id,
        "medication_name": med["name"],
        "dose_time": now.isoformat(),
        "amount_given": dose.amount_given,
        "who_gave": dose.who_gave or current_member.name,
        "note": dose.note,
        "logged_by_member_id": current_member.id,
        "logged_by_member_name": current_member.name,
        "editable_until": (now + timedelta(minutes=10)).isoformat()
    }
    await sb_insert("dose_logs", dose_doc)
    
    return DoseLog(**dose_doc)

@api_router.get("/dose-logs")
async def get_dose_logs(medication_id: Optional[str] = None, current_member: Member = Depends(get_current_member)):
    query = {"care_team_id": current_member.care_team_id}
    if medication_id:
        query["medication_id"] = medication_id
    
    logs = await sb_select("dose_logs", "*", query, limit=100, order="dose_time", desc=True)
    return [DoseLog(**log) for log in logs]

# Symptom Events & Triage
@api_router.post("/symptom-events")
async def create_symptom_event(event: SymptomEventCreate, current_member: Member = Depends(get_current_member)):
    now = datetime.now(timezone.utc)
    event_doc = {
        "id": str(uuid.uuid4()),
        "care_team_id": current_member.care_team_id,
        **event.model_dump(),
        "event_time": now.isoformat(),
        "created_by_member_id": current_member.id,
        "created_by_member_name": current_member.name,
        "editable_until": (now + timedelta(minutes=10)).isoformat()
    }
    await sb_insert("symptom_events", event_doc)
    
    # Track analytics
    await track_analytics_event("triage_started", current_member.care_team_id, current_member.role, {
        "severity": event.severity,
        "symptom_count": len(event.symptoms)
    })
    
    return SymptomEvent(**event_doc)

@api_router.get("/symptom-events")
async def get_symptom_events(current_member: Member = Depends(get_current_member)):
    events = await sb_select("symptom_events", "*", {"care_team_id": current_member.care_team_id}, limit=50, order="event_time", desc=True)
    return [SymptomEvent(**e) for e in events]

@api_router.post("/skin-wound-events")
async def create_skin_wound_event(event: SkinWoundEventCreate, current_member: Member = Depends(get_current_member)):
    now = datetime.now(timezone.utc)
    event_doc = {
        "id": str(uuid.uuid4()),
        "care_team_id": current_member.care_team_id,
        **event.model_dump(),
        "event_time": now.isoformat(),
        "created_by_member_id": current_member.id,
        "created_by_member_name": current_member.name,
        "editable_until": (now + timedelta(minutes=10)).isoformat()
    }
    await sb_insert("skin_wound_events", event_doc)
    return SkinWoundEvent(**event_doc)

@api_router.get("/skin-wound-events")
async def get_skin_wound_events(current_member: Member = Depends(get_current_member)):
    events = await sb_select("skin_wound_events", "*", {"care_team_id": current_member.care_team_id}, limit=50, order="event_time", desc=True)
    visible = [e for e in events if not e.get("deleted_at")]
    return [SkinWoundEvent(**e) for e in visible]

@api_router.post("/skin-wound-events/{event_id}/archive")
async def archive_skin_wound_event(event_id: str, current_member: Member = Depends(get_current_member)):
    payload = {"deleted_at": datetime.now(timezone.utc).isoformat()}
    res = sb.table("skin_wound_events").update(payload).eq("id", event_id).eq("care_team_id", current_member.care_team_id).execute()
    return {"success": True, "event_id": event_id, "result": res.data}

@api_router.post("/nurse-contact")
async def log_nurse_contact(
    symptom_event_id: Optional[str] = None,
    contact_method: str = "call",
    current_member: Member = Depends(get_current_member)
):
    contact_doc = {
        "id": str(uuid.uuid4()),
        "care_team_id": current_member.care_team_id,
        "symptom_event_id": symptom_event_id,
        "contact_method": contact_method,
        "status": "attempted",
        "attempted_at": datetime.now(timezone.utc).isoformat(),
        "attempted_by_member_id": current_member.id
    }
    await sb_insert("nurse_contacts", contact_doc)
    
    # Track analytics
    await track_analytics_event("nurse_contact_attempted", current_member.care_team_id, current_member.role, {
        "method": contact_method
    })
    
    return NurseContactAttempt(**contact_doc)

# Observations
@api_router.post("/observations")
async def create_observation(obs: ObservationCreate, current_member: Member = Depends(get_current_member)):
    obs_doc = {
        "id": str(uuid.uuid4()),
        "care_team_id": current_member.care_team_id,
        **obs.model_dump(),
        "created_at": datetime.now(timezone.utc).isoformat(),
        "created_by_member_id": current_member.id,
        "created_by_member_name": current_member.name
    }
    await sb_insert("observations", obs_doc)
    return Observation(**obs_doc)

@api_router.get("/observations")
async def get_observations(current_member: Member = Depends(get_current_member)):
    obs = await sb_select("observations", "*", {"care_team_id": current_member.care_team_id}, limit=100, order="created_at", desc=True)
    return [Observation(**o) for o in obs]

# Moments
@api_router.post("/moments")
async def create_moment(moment: MomentCreate, current_member: Member = Depends(get_current_member)):
    if current_member.role == "professional":
        raise HTTPException(status_code=403, detail="Professional caregivers cannot create moments")
    
    moment_doc = {
        "id": str(uuid.uuid4()),
        "care_team_id": current_member.care_team_id,
        **moment.model_dump(),
        "created_at": datetime.now(timezone.utc).isoformat(),
        "created_by_member_id": current_member.id,
        "created_by_member_name": current_member.name
    }
    await sb_insert("moments", moment_doc)
    
    # Track analytics
    await track_analytics_event("moments_entry_created", current_member.care_team_id, current_member.role, {
        "category": moment.category
    })
    
    return Moment(**moment_doc)

@api_router.get("/moments")
async def get_moments(current_member: Member = Depends(get_current_member)):
    if current_member.role == "professional":
        return []
    
    query = {"care_team_id": current_member.care_team_id}
    
    # Remote/secondary only see care_team visibility
    if current_member.role in ["remote", "secondary"]:
        query["visibility"] = "care_team"
    elif current_member.role == "primary":
        # Primary sees all
        pass
    
    moments = await sb_select("moments", "*", query, limit=1000, order="created_at", desc=True)
    return [Moment(**m) for m in moments]

# Care Plan
@api_router.get("/care-plan")
async def get_care_plan(current_member: Member = Depends(get_current_member)):
    plans = await sb_select("care_plans", "*", {"care_team_id": current_member.care_team_id}, limit=1)
    plan = plans[0] if plans else None
    if not plan:
        # Create default
        plan = {
            "care_team_id": current_member.care_team_id,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "updated_by_member_id": current_member.id
        }
        await sb_insert("care_plans", plan)
    return CarePlan(**plan)

@api_router.put("/care-plan")
async def update_care_plan(updates: CarePlanUpdate, current_member: Member = Depends(get_current_member)):
    if current_member.role not in ["primary", "secondary"]:
        raise HTTPException(status_code=403, detail="Only primary/secondary can update care plan")
    
    update_doc = {
        **{k: v for k, v in updates.model_dump().items() if v is not None},
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "updated_by_member_id": current_member.id
    }
    
    updated = await sb_update("care_plans", update_doc, {"care_team_id": current_member.care_team_id})
    if not updated:
        base = {
            "care_team_id": current_member.care_team_id,
            "updated_at": update_doc["updated_at"],
            "updated_by_member_id": current_member.id
        }
        await sb_insert("care_plans", {**base, **update_doc})
    
    plans = await sb_select("care_plans", "*", {"care_team_id": current_member.care_team_id}, limit=1)
    plan = plans[0] if plans else None
    return CarePlan(**plan)

# Calendar
@api_router.post("/calendar-events")
async def create_calendar_event(event: CalendarEventCreate, current_member: Member = Depends(get_current_member)):
    event_doc = {
        "id": str(uuid.uuid4()),
        "care_team_id": current_member.care_team_id,
        **event.model_dump(),
        "created_at": datetime.now(timezone.utc).isoformat(),
        "created_by_member_id": current_member.id
    }
    await sb_insert("calendar_events", event_doc)
    return CalendarEvent(**event_doc)

@api_router.get("/calendar-events")
async def get_calendar_events(current_member: Member = Depends(get_current_member)):
    events = await sb_select("calendar_events", "*", {"care_team_id": current_member.care_team_id}, limit=1000, order="date", desc=False)
    return [CalendarEvent(**e) for e in events]

# Daily Check-ins
@api_router.get("/check-in/today")
async def get_today_checkin(current_member: Member = Depends(get_current_member)):
    # Simple rotating questions
    questions = [
        "How are you feeling today?",
        "What's one thing going well?",
        "Is there anything you need support with?",
        "How did you sleep last night?",
        "What's your energy level today?"
    ]
    
    # Check if already completed today
    today = datetime.now(timezone.utc).date().isoformat()
    recent = await sb_select(
        "check_ins",
        "*",
        {"care_team_id": current_member.care_team_id, "member_id": current_member.id},
        limit=20,
        order="created_at",
        desc=True
    )
    for existing in recent:
        if str(existing.get("created_at", "")).startswith(today):
            return {"completed": True, "response": existing.get("response")}
    
    # Return today's question (based on day of year)
    day_of_year = datetime.now(timezone.utc).timetuple().tm_yday
    question = questions[day_of_year % len(questions)]
    
    return {"completed": False, "question": question, "question_id": str(day_of_year)}

@api_router.post("/check-in")
async def submit_checkin(response: CheckInResponse, current_member: Member = Depends(get_current_member)):
    checkin_doc = {
        "id": str(uuid.uuid4()),
        "care_team_id": current_member.care_team_id,
        "member_id": current_member.id,
        "question_text": "",  # Could store from previous call
        "response": response.response,
        "created_at": datetime.now(timezone.utc).isoformat()
    }
    await sb_insert("check_ins", checkin_doc)
    
    # Track analytics
    await track_analytics_event("check_in_completed", current_member.care_team_id, current_member.role)
    
    return {"message": "Check-in saved"}

# Professional Caregiver Shift Notes
@api_router.post("/shift-notes")
async def create_shift_note(note: ShiftNoteCreate, current_member: Member = Depends(get_current_member)):
    if current_member.role != "professional":
        raise HTTPException(status_code=403, detail="Only professional caregivers can create shift notes")
    
    note_doc = {
        "id": str(uuid.uuid4()),
        "care_team_id": current_member.care_team_id,
        "member_id": current_member.id,
        "member_name": current_member.name,
        **note.model_dump(),
        "created_at": datetime.now(timezone.utc).isoformat()
    }
    await sb_insert("shift_notes", note_doc)
    return ShiftNote(**note_doc)

@api_router.get("/shift-notes")
async def get_shift_notes(current_member: Member = Depends(get_current_member)):
    query = {"care_team_id": current_member.care_team_id}
    
    # Non-primary members only see non-flagged notes
    if current_member.role != "primary":
        query["flag_for_primary_only"] = False
    
    notes = await sb_select("shift_notes", "*", query, limit=50, order="shift_date", desc=True)
    return [ShiftNote(**n) for n in notes]

# Current user info
@api_router.get("/me")
async def get_current_user(current_member: Member = Depends(get_current_member)):
    teams = await sb_select("care_teams", "*", {"id": current_member.care_team_id}, limit=1)
    team = teams[0] if teams else None
    return {
        "member": current_member,
        "care_team": CareTeam(**team) if team else None
    }

app.include_router(api_router)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
