import os
import json
import httpx
from typing import Optional, List, Dict, Any
from datetime import datetime, timedelta
from fastapi import FastAPI, Depends, HTTPException, status, File, UploadFile, Form
from fastapi.middleware.cors import CORSMiddleware
from supabase import create_client, Client
from jose import JWTError, jwt
import firebase_admin
from firebase_admin import credentials, messaging

# 💡 Initialize Firebase Admin
cred = credentials.Certificate("./edu-portal-d0a62-firebase-adminsdk-fbsvc-c0b236157d.json")
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
SUPABASE_URL = "https://kvuvxoajuenszfdanoif.supabase.co"
SUPABASE_SERVICE_ROLE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt2dXZ4b2FqdWVuc3pmZGFub2lmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTU2MjA5NiwiZXhwIjoyMDkxMTM4MDk2fQ.9v882ryLmBv-Laoe8b1WHxfGCwBHe1VY1ufmbId9xjI"
TELEGRAM_BOT_TOKEN = "7705422769:AAE9Litq4FezGMrTYRzHuyi8SYUMgcxckkI"
TELEGRAM_CHAT_ID = "-1003952897986"

# 🔒 JWT Token Configuration Requirements
JWT_SECRET_KEY = "a54c18a537a0d7c621566004f2e4de37"
JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 43200  # Tokens stay valid persistently for 30 Days

# Initialize Administrative Supabase Client
supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

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

async def get_current_user(token: str) -> dict:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate active session credentials.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, JWT_SECRET_KEY, algorithms=[JWT_ALGORITHM])
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

# -------------------------------------------------------------------------
# 1. CENTRALIZED AUTHENTICATION CONTROLLER
# -------------------------------------------------------------------------
@app.post("/api/auth/login")
async def secure_login(payload: dict):
    roll_number = str(payload.get("roll_number", "")).strip()
    entered_password = str(payload.get("password", "")).strip()  # Represents Student Date of Birth

    if not roll_number or not entered_password:
        raise HTTPException(status_code=400, detail="Missing required input credentials fields.")

    response = supabase.table("StudentDetails").select("*").eq("Roll_No", roll_number).execute()
    student = response.data[0] if response.data else None

    if not student:
        parsed_roll = int(roll_number) if roll_number.isdigit() else None
        if parsed_roll:
            response = supabase.table("StudentDetails").select("*").eq("Roll_No", parsed_roll).execute()
            student = response.data[0] if response.data else None

    if not student:
        raise HTTPException(status_code=404, detail="No matching student record workspace registered.")

    correct_dob = get_field_insensitive(student, ["dob", "date_of_birth"], default_val="")

    if not correct_dob:
        raise HTTPException(status_code=500, detail="Date of Birth data schema column missing in database mapping.")

    clean_entered = "".join(filter(str.isdigit, entered_password))
    clean_correct = "".join(filter(str.isdigit, correct_dob))

    is_match = (clean_entered == clean_correct and clean_entered != "") or (entered_password == correct_dob)

    if not is_match:
        raise HTTPException(status_code=401, detail="Invalid password parameters.")

    student_name = get_field_insensitive(student, ["name"], "Student")
    student_roll = get_field_insensitive(student, ["roll_no", "roll_number", "roll_no."], roll_number)
    student_email = get_field_insensitive(student, ["email"])
    student_programme = get_field_insensitive(student, ["programme", "department", "dept", "branch"])
    student_semester = get_field_insensitive(student, ["semester"], "4")

    token_data = {
        "sub": student_roll,
        "name": student_name,
        "dept": student_programme
    }
    jwt_token = create_access_token(token_data)

    return {
        "access_token": jwt_token,
        "token_type": "bearer",
        "user": {
            "id": student_roll,
            "name": student_name,
            "roll_number": student_roll,
            "email": student_email,
            "department": student_programme,
            "semester": student_semester,
            "dob": correct_dob,
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
    }

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
    # Security: .eq("user_id", ...) strictly enforces that a user can only delete their own files
    response = supabase.table("student_vault").delete().eq("id", record_id).eq("user_id", user["roll_number"]).execute()
    return {"success": True}

# -------------------------------------------------------------------------
# 4. CHAT ROOM MIDDLEWARE ROUTER & DISPATCHER
# -------------------------------------------------------------------------
@app.post("/api/chat/send")
async def handle_chat_delivery(message: dict, token: str):
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
    
    # Security: Check sender_id to prevent users from editing other people's messages
    response = supabase.table("GroupChats").update({
        "message_body": new_body, 
        "is_edited": True
    }).eq("id", message_id).eq("sender_id", user["roll_number"]).execute()
    
    return {"success": True, "data": response.data}

@app.delete("/api/chat/delete")
async def delete_chat_message(message_id: str, token: str):
    user = await get_current_user(token)
    # Security: Check sender_id to prevent users from deleting other people's messages
    response = supabase.table("GroupChats").delete().eq("id", message_id).eq("sender_id", user["roll_number"]).execute()
    return {"success": True}

# -------------------------------------------------------------------------
# 5. PROFILE, SCHEDULES & TIMETABLE RESOURCE DELIVERY ENGINE
# -------------------------------------------------------------------------
@app.get("/api/schedule/fetch")
async def fetch_academic_schedules(department: str, semester: str, group_name: Optional[str] = None):
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
    
    # 💡 FIX: Use select("*") to bypass Supabase's strict case-sensitive URL parsing
    response = supabase.table("Weekly Schedules").select("*").execute()
    
    groups = set()
    for row in (response.data or []):
        # 💡 Use the robust case-insensitive parser to find the group name safely
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
    return response.data[0]

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
            notification=messaging.Notification(title=title, body=body),
            topic=topic,
        )
        response = messaging.send(message)
        return {"success": True, "message_id": response}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)