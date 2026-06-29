import os
import json
import httpx
import uuid
import random
import asyncio
from typing import Optional, List, Dict, Any
from datetime import datetime, timedelta
from fastapi import FastAPI, Depends, HTTPException, status, File, UploadFile, Form, staticfiles, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, RedirectResponse
from supabase import create_client, Client
from jose import JWTError, jwt
import firebase_admin
from firebase_admin import credentials, messaging
from dotenv import load_dotenv

# Load credentials and secrets from .env file
load_dotenv()

# Initialize Firebase Admin
cred_dict = {
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
    "universe_domain": os.environ.get("universe_domain", "googleapis.com")
}

try:
    cred = credentials.Certificate(cred_dict)
    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred)
except Exception as e:
    print(f"Firebase Init Warning: {e}")

app = FastAPI(title="EduPortal Extended Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- ENVIRONMENT VARIABLES ---
SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
RESEND_API_KEY = os.environ.get("RESEND_API_KEY") 

JWT_SECRET_KEY = os.environ.get("JWT_SECRET_KEY", "eduportal_super_secret_key_change_in_prod")
JWT_ALGORITHM = os.environ.get("JWT_ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.environ.get("ACCESS_TOKEN_EXPIRE_MINUTES", "1440")) # 24 Hours

# --- TELEGRAM VAULT/CHAT STORAGE VARIABLES ---
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

# --- Helper Functions ---
def get_field_insensitive(data: Dict[str, Any], target_keys: List[str], default_val: str = "") -> str:
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
    try:
        payload = jwt.decode(token, JWT_SECRET_KEY, algorithms=[JWT_ALGORITHM])
        roll_number: str = payload.get("sub")
        if roll_number is None:
            raise HTTPException(status_code=401, detail="Invalid authentication token")
        return {"roll_number": roll_number, "name": payload.get("name")}
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

@app.get("/")
async def serve_home():
    return {"status": "EduPortal API Gateway is Active"}

# -------------------------------------------------------------------------
# 1. AUTHENTICATION & MULTI-DEVICE MANAGEMENT
# -------------------------------------------------------------------------
@app.post("/api/auth/login")
async def secure_login(payload: dict):
    roll_number = str(payload.get("roll_number", "")).strip()
    entered_password = str(payload.get("password", "")).strip()
    device_id = str(payload.get("device_id", "")).strip()

    if not roll_number or not entered_password:
        raise HTTPException(status_code=400, detail="Missing credentials.")

    response = supabase.table("StudentDetails").select("*").eq("Roll_No", roll_number).execute()
    student = response.data[0] if response.data else None
    
    if not student:
        raise HTTPException(status_code=404, detail="Student account not found.")

    correct_pass = get_field_insensitive(student, ["password"])
    if not correct_pass:
        correct_pass = get_field_insensitive(student, ["dob", "date_of_birth"])
    
    if entered_password != correct_pass:
        raise HTTPException(status_code=401, detail="Invalid password.")
        
    current_device = get_field_insensitive(student, ["device_id"])
    if current_device and current_device != device_id and device_id != "":
        supabase.table("StudentDetails").update({
            "device_id": device_id, 
            "last_active": datetime.utcnow().isoformat()
        }).eq("Roll_No", roll_number).execute()
    elif not current_device and device_id != "":
        supabase.table("StudentDetails").update({"device_id": device_id}).eq("Roll_No", roll_number).execute()

    jwt_token = create_access_token({"sub": str(student["Roll_No"]), "name": get_field_insensitive(student, ["name"])})

    return {
        "access_token": jwt_token,
        "subscribed_group": get_field_insensitive(student, ["subscribed_schedule_group"]),
        "user": {
            "id": str(student["Roll_No"]),
            "name": get_field_insensitive(student, ["name"], "Student"),
            "roll_number": str(student["Roll_No"]),
            "email": get_field_insensitive(student, ["email"]),
            "department": get_field_insensitive(student, ["programme", "department", "dept"]),
            "semester": get_field_insensitive(student, ["semester"], "4"),
        }
    }

# -------------------------------------------------------------------------
# 2. OTP PASSWORD RESET ENGINE
# -------------------------------------------------------------------------
@app.post("/api/auth/request-otp")
async def request_otp(payload: dict):
    email = payload.get("email", "").strip()
    if not email:
        raise HTTPException(status_code=400, detail="Email is required.")

    response = supabase.table("StudentDetails").select("Roll_No").eq("Email", email).execute()
    if not response.data:
        raise HTTPException(status_code=404, detail="Email not registered to any student.")
        
    otp = str(random.randint(100000, 999999))
    
    supabase.table("otp_verifications").upsert({
        "email": email, 
        "otp": otp, 
        "expires_at": (datetime.utcnow() + timedelta(minutes=10)).isoformat()
    }).execute()
    
    if RESEND_API_KEY:
        async with httpx.AsyncClient() as client:
            await client.post(
                "https://api.resend.com/emails", 
                headers={"Authorization": f"Bearer {RESEND_API_KEY}"}, 
                json={
                    "from": "onboarding@resend.dev", 
                    "to": email, 
                    "subject": "EduPortal Password Reset Request",
                    "html": f"<div style='font-family: sans-serif;'><h2>Your EduPortal Reset Code is: <span style='color: #2563eb;'>{otp}</span></h2><p>Valid for 10 minutes.</p></div>"
                }
            )
    return {"success": True, "message": "OTP sent to email."}

@app.post("/api/auth/reset-password")
async def reset_password(payload: dict):
    email = payload.get("email")
    otp = payload.get("otp")
    new_password = payload.get("new_password")
    
    verify_res = supabase.table("otp_verifications").select("*").eq("email", email).eq("otp", otp).execute()
    if not verify_res.data:
        raise HTTPException(status_code=401, detail="Invalid or incorrect OTP.")
        
    expiration = datetime.fromisoformat(verify_res.data[0]["expires_at"])
    if datetime.utcnow() > expiration:
        raise HTTPException(status_code=401, detail="OTP Expired. Please request a new one.")
        
    supabase.table("StudentDetails").update({"Password": new_password}).eq("Email", email).execute()
    supabase.table("otp_verifications").delete().eq("email", email).execute()
    
    return {"success": True, "message": "Password updated successfully."}

# -------------------------------------------------------------------------
# 3. CLOUD SYNC (JSONB) - TASKS & ATTENDANCE
# -------------------------------------------------------------------------
@app.post("/api/sync/cloud-data")
async def sync_to_cloud(payload: dict):
    token = payload.get("token")
    if not token:
        raise HTTPException(status_code=401, detail="Token required")
        
    user = await get_current_user(token)
    roll = user["roll_number"]
    
    update_data = {"roll_no": roll}
    
    if "attendance" in payload:
        update_data["attendance_jsonb"] = payload["attendance"]
    if "tasks" in payload:
        update_data["tasks_jsonb"] = payload["tasks"]
        
    if len(update_data) > 1:
        supabase.table("student_cloud_data").upsert(update_data).execute()
        
    return {"success": True}

@app.get("/api/sync/cloud-data")
async def fetch_from_cloud(token: str):
    user = await get_current_user(token)
    response = supabase.table("student_cloud_data").select("*").eq("roll_no", user["roll_number"]).execute()
    
    if response.data:
        return {"success": True, "data": response.data[0]}
    
    return {"success": True, "data": {"attendance_jsonb": {}, "tasks_jsonb": []}}

@app.post("/api/user/update-group")
async def update_schedule_group(payload: dict):
    token = payload.get("token")
    new_group = payload.get("group_name")
    
    user = await get_current_user(token)
    supabase.table("StudentDetails").update({"subscribed_schedule_group": new_group}).eq("Roll_No", user["roll_number"]).execute()
    return {"success": True}

# -------------------------------------------------------------------------
# 4. SCHEDULE OVERRIDES (CANCELLATIONS / HOLIDAYS)
# -------------------------------------------------------------------------
@app.get("/api/schedule/overrides")
async def get_schedule_overrides(group_name: str, date: str):
    response = supabase.table("schedule_overrides").select("override_data_jsonb").eq("group_name", group_name).eq("date", date).execute()
    
    if response.data:
        return {"success": True, "overrides": response.data[0]["override_data_jsonb"]}
    return {"success": True, "overrides": {}}

# -------------------------------------------------------------------------
# 5. EXISTING FIREBASE PUSH NOTIFICATION ROUTES
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

# -------------------------------------------------------------------------
# 6. VAULT & CHAT ATTACHMENTS (TELEGRAM CLOUD UPLOAD)
# -------------------------------------------------------------------------
@app.post("/api/upload")
async def upload_file_to_telegram(file: UploadFile = File(...)):
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        raise HTTPException(status_code=500, detail="Telegram storage credentials are missing in .env")
        
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendDocument"
    
    try:
        file_bytes = await file.read()
        files = {'document': (file.filename, file_bytes)}
        data = {'chat_id': TELEGRAM_CHAT_ID}
        
        async with httpx.AsyncClient() as client:
            response = await client.post(url, data=data, files=files, timeout=60.0)
            
        if response.status_code == 200:
            res_data = response.json()
            file_id = res_data['result']['document']['file_id']
            
            # Resolve the direct download URL for Flutter
            path_url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/getFile?file_id={file_id}"
            async with httpx.AsyncClient() as client:
                path_res = await client.get(path_url)
                
            file_path = path_res.json()['result']['file_path']
            download_url = f"https://api.telegram.org/file/bot{TELEGRAM_BOT_TOKEN}/{file_path}"
            
            return {"success": True, "file_url": download_url, "file_id": file_id}
        else:
            raise HTTPException(status_code=400, detail="Failed to upload file to Telegram Vault")
            
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)