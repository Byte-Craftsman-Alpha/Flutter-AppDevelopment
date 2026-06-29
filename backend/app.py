import os
import json
import httpx
import asyncio
import secrets
import smtplib
from typing import Optional, List, Dict, Any
from datetime import datetime, timedelta
from email.message import EmailMessage
from fastapi import FastAPI, Depends, HTTPException, status, File, UploadFile, Form, staticfiles, BackgroundTasks, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, RedirectResponse
from supabase import create_client, Client
from jose import JWTError, jwt
from passlib.context import CryptContext
import firebase_admin
from firebase_admin import credentials, messaging
from dotenv import load_dotenv

# Load credentials and secrets from .env file
load_dotenv()

# 💡 Initialize Firebase Admin
cred = credentials.Certificate(
    {
        "type": os.environ.get("type"),
        "project_id": os.environ.get("project_id"),
        "private_key_id": os.environ.get("private_key_id"),
        "private_key": os.environ.get("private_key", "").replace('\\n', '\n'),
        "client_email": os.environ.get("client_email"),
        "client_id": os.environ.get("client_id"),
        "auth_uri": os.environ.get("auth_uri"),
        "token_uri": os.environ.get("token_uri"),
        "auth_provider_x509_cert_url": os.environ.get("auth_provider_x509_cert_url"),
        "client_x509_cert_url": os.environ.get("client_x509_cert_url"),
        "universe_domain": os.environ.get("universe_domain")
    }
)
firebase_admin.initialize_app(cred)

app = FastAPI(
    title="EduPortal Backend Gateway",
    description="Secure intermediate backend middleware safeguarding Supabase & Telegram infrastructure."
)

# 🌐 CORS Middleware Settings
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Adjust this to restrict origins once you are ready for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 🔑 System Environment Configurations (Hidden completely from client APKs)
SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID")

# 🔒 JWT Token Configuration Requirements
JWT_SECRET_KEY = os.environ.get("JWT_SECRET_KEY")
JWT_ALGORITHM = os.environ.get("JWT_ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.environ.get("ACCESS_TOKEN_EXPIRE_MINUTES", "1440"))
ADMIN_API_KEY = os.environ.get("ADMIN_API_KEY")

SMTP_HOST = os.environ.get("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USERNAME = os.environ.get("SMTP_USERNAME")
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD")
SMTP_FROM_EMAIL = os.environ.get("SMTP_FROM_EMAIL", SMTP_USERNAME or "")
RESEND_API_KEY = os.environ.get("RESEND_API_KEY")
RESEND_FROM_EMAIL = os.environ.get("RESEND_FROM_EMAIL", SMTP_FROM_EMAIL)

# Initialize Administrative Supabase Client
supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
password_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# 💡 Helper: Case-Insensitive Dictionary Lookup
def get_field_insensitive(data: Dict[str, Any], target_keys: List[str], default_val: str = "") -> str:
    """
    Looks up a dictionary value by matching keys case-insensitively 
    and ignoring space/underscore variations. This eliminates key errors.
    """
    for key, value in data.items():
        normalized_db_key = key.lower().replace(" ", "_").strip()
        if normalized_db_key in target_keys:
            return str(value).strip() if value is not None else default_val
    return default_val

def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, JWT_SECRET_KEY, algorithm=JWT_ALGORITHM)

async def get_current_user(token: Optional[str] = None, authorization: Optional[str] = Header(default=None)) -> dict:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate active session credentials.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        raw_token = token
        if not raw_token and authorization and authorization.lower().startswith("bearer "):
            raw_token = authorization.split(" ", 1)[1].strip()
        if not raw_token:
            raise credentials_exception

        payload = jwt.decode(raw_token, JWT_SECRET_KEY, algorithms=[JWT_ALGORITHM])
        roll_number: str = payload.get("sub")
        if roll_number is None:
            raise credentials_exception
        return {
            "roll_number": roll_number, 
            "name": payload.get("name"), 
            "department": payload.get("dept")
        }
    except JWTError:
        raise credentials_exception

def normalize_identifier(identifier: str) -> str:
    return str(identifier or "").strip().lower()

def verify_password(plain_password: str, password_hash: str) -> bool:
    try:
        return password_context.verify(plain_password, password_hash)
    except Exception:
        return False

def hash_password(plain_password: str) -> str:
    return password_context.hash(plain_password)

def require_admin_key(x_admin_key: Optional[str]) -> None:
    if not ADMIN_API_KEY or x_admin_key != ADMIN_API_KEY:
        raise HTTPException(status_code=403, detail="Admin API key required.")

def build_student_payload(student: Dict[str, Any], fallback_roll: str) -> Dict[str, Any]:
    return {
        "id": get_field_insensitive(student, ["roll_no", "roll_number", "roll_no."], fallback_roll),
        "name": get_field_insensitive(student, ["name"], "Student"),
        "roll_number": get_field_insensitive(student, ["roll_no", "roll_number", "roll_no."], fallback_roll),
        "email": get_field_insensitive(student, ["email"]),
        "department": get_field_insensitive(student, ["programme", "department", "dept", "branch"]),
        "semester": get_field_insensitive(student, ["semester"], "4"),
        "dob": get_field_insensitive(student, ["dob", "date_of_birth"]),
        "Mobile_No": get_field_insensitive(student, ["mobile_no", "mobile", "phone"]),
        "Aadhaar": get_field_insensitive(student, ["aadhaar", "aadhaar_no"]),
        "enrollment_no": get_field_insensitive(student, ["enrollment_no", "enrollment"]),
        "apaar_id": get_field_insensitive(student, ["apaar_id", "apaar"]),
        "address": get_field_insensitive(student, ["address"]),
        "category": get_field_insensitive(student, ["category"]),
        "gender": get_field_insensitive(student, ["gender"]),
        "father_name": get_field_insensitive(student, ["father_name", "father"]),
        "mother_name": get_field_insensitive(student, ["mother_name", "mother"]),
    }

def find_student(identifier: str) -> Optional[Dict[str, Any]]:
    clean_identifier = str(identifier or "").strip()
    if not clean_identifier:
        return None

    response = supabase.table("StudentDetails").select("*").eq("Roll_No", clean_identifier).execute()
    if response.data:
        return response.data[0]

    if clean_identifier.isdigit():
        response = supabase.table("StudentDetails").select("*").eq("Roll_No", int(clean_identifier)).execute()
        if response.data:
            return response.data[0]

    response = supabase.table("StudentDetails").select("*").ilike("Email", clean_identifier).execute()
    return response.data[0] if response.data else None

async def deliver_password_otp(email: str, otp: str) -> None:
    subject = "Your EduPortal password reset OTP"
    body = f"Your EduPortal password reset OTP is {otp}. It expires in 10 minutes."

    if RESEND_API_KEY and RESEND_FROM_EMAIL:
        async with httpx.AsyncClient(timeout=15) as client:
            response = await client.post(
                "https://api.resend.com/emails",
                headers={"Authorization": f"Bearer {RESEND_API_KEY}", "Content-Type": "application/json"},
                json={"from": RESEND_FROM_EMAIL, "to": [email], "subject": subject, "text": body},
            )
            if response.status_code < 300:
                return
            raise HTTPException(status_code=502, detail="OTP email provider rejected the request.")

    if SMTP_USERNAME and SMTP_PASSWORD and SMTP_FROM_EMAIL:
        message = EmailMessage()
        message["Subject"] = subject
        message["From"] = SMTP_FROM_EMAIL
        message["To"] = email
        message.set_content(body)
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as server:
            server.starttls()
            server.login(SMTP_USERNAME, SMTP_PASSWORD)
            server.send_message(message)
        return

    raise HTTPException(status_code=500, detail="No OTP email provider is configured.")

def upsert_user_account(student_payload: Dict[str, Any], password: Optional[str] = None, device_id: Optional[str] = None) -> None:
    now = datetime.utcnow().isoformat()
    record = {
        "roll_number": student_payload["roll_number"],
        "username": normalize_identifier(student_payload["roll_number"]),
        "email": student_payload.get("email"),
        "name": student_payload.get("name"),
        "department": student_payload.get("department"),
        "semester": student_payload.get("semester"),
        "last_seen_at": now,
        "is_online": True,
    }
    if password:
        record["password_hash"] = hash_password(password)
    if device_id:
        record["device_id"] = device_id
    supabase.table("edu_users").upsert(record, on_conflict="roll_number").execute()

# Mount the static directory so assets load correctly
app.mount("/static", staticfiles.StaticFiles(directory="static"), name="static")


@app.get("/")
async def serve_home():
    # Point directly to the file inside the static folder
    return FileResponse("static/index.html")

# -------------------------------------------------------------------------
# 1. CENTRALIZED AUTHENTICATION CONTROLLER
# -------------------------------------------------------------------------
@app.post("/api/auth/login")
async def secure_login(payload: dict):
    roll_number = str(payload.get("roll_number") or payload.get("username") or "").strip()
    entered_password = str(payload.get("password", "")).strip()
    device_id = str(payload.get("device_id", "")).strip()

    if not roll_number or not entered_password:
        raise HTTPException(status_code=400, detail="Missing required input credentials fields.")

    student = find_student(roll_number)
    if not student:
        raise HTTPException(status_code=404, detail="No matching student record workspace registered.")

    student_payload = build_student_payload(student, roll_number)
    student_roll = student_payload["roll_number"]
    account_response = supabase.table("edu_users").select("*").eq("roll_number", student_roll).execute()
    account = account_response.data[0] if account_response.data else None
    password_hash = account.get("password_hash") if account else None

    if password_hash:
        if not verify_password(entered_password, password_hash):
            raise HTTPException(status_code=401, detail="Invalid password parameters.")
    else:
        correct_dob = get_field_insensitive(student, ["dob", "date_of_birth"], default_val="")
        if not correct_dob:
            raise HTTPException(status_code=500, detail="Date of Birth data schema column missing in database mapping.")

        clean_entered = "".join(filter(str.isdigit, entered_password))
        clean_correct = "".join(filter(str.isdigit, correct_dob))
        is_match = (clean_entered == clean_correct and clean_entered != "") or (entered_password == correct_dob)
        if not is_match:
            raise HTTPException(status_code=401, detail="Invalid password parameters.")
        upsert_user_account(student_payload, password=entered_password, device_id=device_id or None)

    upsert_user_account(student_payload, device_id=device_id or None)

    token_data = {
        "sub": student_roll,
        "name": student_payload["name"],
        "dept": student_payload["department"]
    }
    jwt_token = create_access_token(token_data)
    student_payload["subscribed_schedule_group"] = account.get("subscribed_schedule_group") if account else None

    return {
        "access_token": jwt_token,
        "token_type": "bearer",
        "user": student_payload
    }

@app.post("/api/auth/password/request-otp")
async def request_password_reset_otp(payload: dict):
    identifier = str(payload.get("roll_number") or payload.get("username") or payload.get("email") or "").strip()
    student = find_student(identifier)
    if not student:
        raise HTTPException(status_code=404, detail="No matching student record found.")

    student_payload = build_student_payload(student, identifier)
    email = student_payload.get("email")
    if not email:
        raise HTTPException(status_code=400, detail="No email address is registered for this student.")

    otp = f"{secrets.randbelow(1000000):06d}"
    now = datetime.utcnow()
    otp_record = {
        "roll_number": student_payload["roll_number"],
        "email": email,
        "otp_hash": hash_password(otp),
        "expires_at": (now + timedelta(minutes=10)).isoformat(),
        "consumed_at": None,
        "created_at": now.isoformat(),
    }
    supabase.table("password_reset_otps").insert(otp_record).execute()
    upsert_user_account(student_payload)
    await deliver_password_otp(email, otp)

    masked = email
    if "@" in email:
        name, domain = email.split("@", 1)
        masked = f"{name[:2]}***@{domain}"
    return {"success": True, "email": masked}

@app.post("/api/auth/password/reset")
async def reset_password_with_otp(payload: dict):
    identifier = str(payload.get("roll_number") or payload.get("username") or "").strip()
    otp = str(payload.get("otp", "")).strip()
    new_password = str(payload.get("new_password", "")).strip()
    device_id = str(payload.get("device_id", "")).strip()

    if not identifier or not otp or len(new_password) < 6:
        raise HTTPException(status_code=400, detail="Username, OTP, and a 6+ character password are required.")

    student = find_student(identifier)
    if not student:
        raise HTTPException(status_code=404, detail="No matching student record found.")

    student_payload = build_student_payload(student, identifier)
    response = (
        supabase.table("password_reset_otps")
        .select("*")
        .eq("roll_number", student_payload["roll_number"])
        .is_("consumed_at", "null")
        .order("created_at", desc=True)
        .limit(1)
        .execute()
    )
    otp_record = response.data[0] if response.data else None
    if not otp_record:
        raise HTTPException(status_code=400, detail="No active OTP found. Please request a new one.")

    expires_at = datetime.fromisoformat(str(otp_record["expires_at"]).replace("Z", "+00:00")).replace(tzinfo=None)
    if expires_at < datetime.utcnow() or not verify_password(otp, otp_record["otp_hash"]):
        raise HTTPException(status_code=401, detail="Invalid or expired OTP.")

    upsert_user_account(student_payload, password=new_password, device_id=device_id or None)
    supabase.table("password_reset_otps").update({"consumed_at": datetime.utcnow().isoformat()}).eq("id", otp_record["id"]).execute()
    return {"success": True}

@app.post("/api/auth/logout")
async def logout_device(payload: dict, token: str):
    user = await get_current_user(token)
    device_id = str(payload.get("device_id", "")).strip()
    update_payload = {"is_online": False, "last_seen_at": datetime.utcnow().isoformat()}
    query = supabase.table("edu_users").update(update_payload).eq("roll_number", user["roll_number"])
    if device_id:
        query = query.eq("device_id", device_id)
    query.execute()
    return {"success": True}

@app.post("/api/auth/heartbeat")
async def heartbeat(payload: dict, token: str):
    user = await get_current_user(token)
    device_id = str(payload.get("device_id", "")).strip()
    update_payload = {"is_online": True, "last_seen_at": datetime.utcnow().isoformat()}
    if device_id:
        update_payload["device_id"] = device_id
    supabase.table("edu_users").update(update_payload).eq("roll_number", user["roll_number"]).execute()
    return {"success": True}

@app.get("/api/sync/bootstrap")
async def sync_bootstrap(token: str):
    user = await get_current_user(token)
    account_response = supabase.table("edu_users").select("*").eq("roll_number", user["roll_number"]).execute()
    account = account_response.data[0] if account_response.data else {}
    data_response = supabase.table("student_cloud_state").select("*").eq("roll_number", user["roll_number"]).execute()
    state = data_response.data[0] if data_response.data else {}
    return {
        "subscribed_schedule_group": account.get("subscribed_schedule_group"),
        "tasks": state.get("tasks") or [],
        "attendance": state.get("attendance") or [],
        "updated_at": state.get("updated_at"),
    }

@app.post("/api/sync/state")
async def sync_student_state(payload: dict, token: str):
    user = await get_current_user(token)
    record = {
        "roll_number": user["roll_number"],
        "tasks": payload.get("tasks") or [],
        "attendance": payload.get("attendance") or [],
        "updated_at": datetime.utcnow().isoformat(),
    }
    supabase.table("student_cloud_state").upsert(record, on_conflict="roll_number").execute()
    return {"success": True, "updated_at": record["updated_at"]}

@app.post("/api/user/schedule-subscription")
async def update_schedule_subscription(payload: dict, token: str):
    user = await get_current_user(token)
    group_name = str(payload.get("group_name", "")).strip()
    group_value = group_name if group_name else None
    supabase.table("edu_users").update({
        "subscribed_schedule_group": group_value,
        "updated_at": datetime.utcnow().isoformat(),
    }).eq("roll_number", user["roll_number"]).execute()
    return {"success": True, "subscribed_schedule_group": group_value}

@app.post("/api/admin/schedule/override")
async def upsert_schedule_override(payload: dict, x_admin_key: Optional[str] = Header(default=None)):
    require_admin_key(x_admin_key)
    group_name = str(payload.get("group_name", "")).strip()
    date = str(payload.get("date", "")).strip()
    override_data = payload.get("override_data")
    if not group_name or not date or override_data is None:
        raise HTTPException(status_code=400, detail="group_name, date, and override_data are required.")
    record = {
        "group_name": group_name,
        "date": date,
        "override_data": override_data,
        "status": payload.get("status", "active"),
        "note": payload.get("note"),
        "updated_at": datetime.utcnow().isoformat(),
    }
    supabase.table("schedule_overrides").upsert(record, on_conflict="group_name,date").execute()
    return {"success": True, "record": record}

@app.delete("/api/admin/schedule/override")
async def delete_schedule_override(group_name: str, date: str, x_admin_key: Optional[str] = Header(default=None)):
    require_admin_key(x_admin_key)
    supabase.table("schedule_overrides").delete().eq("group_name", group_name).eq("date", date).execute()
    return {"success": True}

# -------------------------------------------------------------------------
# 2. TELEGRAM PROXY (Isolating the Bot Token from the APK)
# -------------------------------------------------------------------------
@app.get("/api/files/resolve")
async def resolve_cloud_file(file_id: str, token: str):
    """Securely translates Telegram File IDs into Downloadable URLs."""
    await get_current_user(token) # Validate session exists
    async with httpx.AsyncClient() as client:
        uri = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/getFile?file_id={file_id}"
        response = await client.get(uri)
        if response.status_code == 200:
            data = response.json()
            if data.get("ok"):
                file_path = data["result"]["file_path"]
                return {"url": f"https://api.telegram.org/file/bot{TELEGRAM_BOT_TOKEN}/{file_path}"}
        raise HTTPException(status_code=404, detail="Could not resolve file link.")

@app.post("/api/chat/upload_file")
async def chat_file_upload(token: str = Form(...), file: UploadFile = File(...)):
    """Uploads a file directly to Telegram for group chats without touching Supabase."""
    await get_current_user(token)
    async with httpx.AsyncClient() as client:
        telegram_url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendDocument"
        file_bytes = await file.read()
        files = {"document": (file.filename, file_bytes)}
        data = {"chat_id": TELEGRAM_CHAT_ID}
        
        tg_response = await client.post(telegram_url, files=files, data=data)
        if tg_response.status_code != 200:
            raise HTTPException(status_code=500, detail="Cloud storage cluster handshake failed.")
            
        tg_data = tg_response.json()
        return {
            "success": True, 
            "file_id": tg_data["result"]["document"]["file_id"],
            "file_name": file.filename,
            "file_size": len(file_bytes),
            "extension": file.filename.split(".")[-1] if "." in file.filename else "file"
        }

# -------------------------------------------------------------------------
# 3. DOCUMENT VAULT MANAGEMENT PIPELINE (Per-user sandboxing)
# -------------------------------------------------------------------------
@app.post("/api/vault/upload")
async def vault_upload_pipeline(token: str = Form(...), file: UploadFile = File(...)):
    user = await get_current_user(token)
    
    async with httpx.AsyncClient() as client:
        telegram_url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendDocument"
        file_bytes = await file.read()
        
        files = {"document": (file.filename, file_bytes)}
        data = {"chat_id": TELEGRAM_CHAT_ID}
        
        tg_response = await client.post(telegram_url, files=files, data=data)
        if tg_response.status_code != 200:
            raise HTTPException(status_code=500, detail="Cloud storage cluster handshake failed.")
            
        tg_data = tg_response.json()
        cloud_file_id = tg_data["result"]["document"]["file_id"]

    record_id = str(int(datetime.utcnow().timestamp() * 1000))
    vault_entry = {
        "id": record_id,
        "user_id": user["roll_number"],
        "file_id": cloud_file_id,
        "file_name": file.filename,
        "file_size": len(file_bytes),
        "extension": file.filename.split(".")[-1] if "." in file.filename else "file",
        "created_at": datetime.utcnow().isoformat()
    }
    
    supabase.table("student_vault").insert(vault_entry).execute()
    return {"success": True, "record": vault_entry}

@app.get("/api/vault/records")
async def get_vault_records(token: str):
    user = await get_current_user(token)
    response = supabase.table("student_vault").select("*").eq("user_id", user["roll_number"]).execute()
    return response.data

@app.delete("/api/vault/delete")
async def delete_vault_record(record_id: str, token: str):
    user = await get_current_user(token)
    response = supabase.table("student_vault").delete().eq("id", record_id).eq("user_id", user["roll_number"]).execute()
    return {"success": True}

# -------------------------------------------------------------------------
# 4. CHAT ROOM MIDDLEWARE ROUTER & DISPATCHER
# -------------------------------------------------------------------------
@app.post("/api/chat/send")
async def handle_chat_delivery(message: dict, token: str, background_tasks: BackgroundTasks):
    user = await get_current_user(token)
    
    chat_entry = {
        "sender_id": user["roll_number"],
        "sender_name": user["name"],
        "sender_roll": user["roll_number"],
        "message_body": message.get("body"),
        "has_attachment": message.get("has_attachment", False),
        "attachment_meta": message.get("attachment_meta"),
        "reply_to_id": message.get("reply_to_id"),
        "reply_to_name": message.get("reply_to_name"),
        "reply_to_body": message.get("reply_to_body"),
        "created_at": datetime.utcnow().isoformat()
    }
    
    db_response = supabase.table("GroupChats").insert(chat_entry).execute()
    
    background_tasks.add_task(
        broadcast_notification,
        title=f"New Message from {user['name']}",
        body=chat_entry["message_body"][:100] + ("..." if len(chat_entry["message_body"]) > 100 else ""),
        topic="general"
    )
    
    return {"success": True, "data": db_response.data}

@app.get("/api/chat/history")
async def get_chat_history(token: str):
    await get_current_user(token)
    response = supabase.table("GroupChats").select("*").order("created_at", desc=True).limit(100).execute()
    return response.data

@app.put("/api/chat/update")
async def edit_chat_message(payload: dict, token: str):
    user = await get_current_user(token)
    message_id = payload.get("message_id")
    new_body = payload.get("new_body")
    
    if not message_id or not new_body:
        raise HTTPException(status_code=400, detail="Missing message_id or new_body parameters.")
    
    response = supabase.table("GroupChats").update({
        "message_body": new_body, 
        "is_edited": True
    }).eq("id", message_id).eq("sender_id", user["roll_number"]).execute()
    
    return {"success": True, "data": response.data}

@app.delete("/api/chat/delete")
async def delete_chat_message(message_id: str, token: str):
    user = await get_current_user(token)
    response = supabase.table("GroupChats").delete().eq("id", message_id).eq("sender_id", user["roll_number"]).execute()
    return {"success": True}

# -------------------------------------------------------------------------
# 5. PROFILE, SCHEDULES & TIMETABLE RESOURCE DELIVERY ENGINE
# -------------------------------------------------------------------------
@app.get("/api/schedule/fetch")
async def fetch_academic_schedules(
    department: str,
    semester: str,
    group_name: Optional[str] = None,
    date: Optional[str] = None,
):
    if department == "Calendar" and semester == "Events":
        response = supabase.table("Monthly Calendar").select("*").execute()
        return response.data

    response = supabase.table("Weekly Schedules").select("*").execute()
    all_schedules = response.data or []

    if group_name:
        matched_by_group = []
        for row in all_schedules:
            row_group = get_field_insensitive(row, ["schedulegroupname", "schedule_group_name", "group_name", "group"])
            if row_group.lower() == group_name.lower():
                matched_by_group.append(row)
        if matched_by_group:
            if date:
                override_response = (
                    supabase.table("schedule_overrides")
                    .select("*")
                    .eq("group_name", group_name)
                    .eq("date", date)
                    .execute()
                )
                if override_response.data:
                    override = override_response.data[0]
                    patched = dict(matched_by_group[0])
                    patched["ScheduleLists"] = override.get("override_data") or []
                    patched["schedule_lists"] = override.get("override_data") or []
                    patched["schedule_override"] = {
                        "date": override.get("date"),
                        "status": override.get("status"),
                        "note": override.get("note"),
                        "updated_at": override.get("updated_at"),
                    }
                    return [patched]
            return matched_by_group

    matched_by_filters = []
    for row in all_schedules:
        row_dept = get_field_insensitive(row, ["department", "programme", "dept", "branch", "course"])
        row_sem = get_field_insensitive(row, ["semester", "sem"])
        if row_dept.lower() == department.lower() and row_sem.lower() == semester.lower():
            matched_by_filters.append(row)

    return matched_by_filters

@app.get("/api/schedule/groups")
async def get_schedule_groups(token: str):
    await get_current_user(token)
    response = supabase.table("Weekly Schedules").select("*").execute()
    
    groups = set()
    for row in (response.data or []):
        group_name = get_field_insensitive(
            row, 
            ["schedulegroupname", "schedule_group_name", "group_name", "group"]
        )
        if group_name:
            groups.add(group_name)
            
    return sorted(list(groups))

@app.get("/api/profile/sync")
async def sync_profile(token: str):
    user = await get_current_user(token)
    response = supabase.table("StudentDetails").select("*").eq("Roll_No", user["roll_number"]).execute()
    if not response.data:
        raise HTTPException(status_code=404, detail="Student record not found.")
    
    student = response.data[0]
    
    account_response = supabase.table("edu_users").select("*").eq("roll_number", user["roll_number"]).execute()
    account = account_response.data[0] if account_response.data else {}
    profile = build_student_payload(student, user["roll_number"])
    profile["subscribed_schedule_group"] = account.get("subscribed_schedule_group")
    profile["device_id"] = account.get("device_id")
    profile["is_online"] = account.get("is_online", False)
    profile["last_seen_at"] = account.get("last_seen_at")
    return profile

@app.get("/api/directory/staff")
async def fetch_staff_directory(token: str):
    await get_current_user(token)
    try:
        response = supabase.table("staff_directory").select("*").execute()
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/library/books")
async def fetch_library_books(token: str):
    await get_current_user(token)
    try:
        response = supabase.table("library_books").select("*").execute()
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# -------------------------------------------------------------------------
# 6. FIREBASE NOTIFICATION DISPATCHER
# -------------------------------------------------------------------------
@app.post("/api/notifications/send")
async def send_push_notification(title: str, body: str, target_device_token: str):
    try:
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={"click_action": "FLUTTER_NOTIFICATION_CLICK", "type": "chat_alert"},
            token=target_device_token,
        )
        response = messaging.send(message)
        return {"success": True, "message_id": response}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to send notification: {str(e)}")

@app.post("/api/notifications/broadcast")
async def broadcast_notification(title: str, body: str, topic: str):
    try:
        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            topic=topic,
            android=messaging.AndroidConfig(priority='high'),
            apns=messaging.APNSConfig(
                headers={'apns-priority': '10'},
                payload=messaging.APNSPayload(aps=messaging.Aps(sound='default'))
            )
        )
        response = messaging.send(message)
        return {"success": True, "message_id": response}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
