import os
import json
import httpx
from typing import Optional
from datetime import datetime, timedelta
from fastapi import FastAPI, Depends, HTTPException, status, File, UploadFile, Form
from fastapi.middleware.cors import CORSMiddleware
from supabase import create_client, Client
from jose import JWTError, jwt

app = FastAPI(
    title="EduPortal Backend Gateway",
    description="Secure intermediate backend middleware safeguarding Supabase & Telegram infrastructure."
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # Tighten this to your live domain/IP deployment configurations later
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 🔑 System Environment Configurations (Hidden completely from client APKs)
SUPABASE_URL = "https://your-supabase-project.supabase.co"
SUPABASE_SERVICE_ROLE_KEY = "YOUR_SUPABASE_SERVICE_ROLE_KEY" # Grants secure administrative control bypass
TELEGRAM_BOT_TOKEN = "7705422769:AAE9Litq4FezGMrTYRzHuyi8SYUMgcxckkI"
TELEGRAM_CHAT_ID = "-1003952897986"

# JWT Token Configuration Requirements
JWT_SECRET_KEY = "SUPER_SECRET_COMPLEX_RANDOM_STRING_FOR_EDUPORTAL_BACKEND"
JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 43200 # Tokens stay valid persistently for 30 Days

# Initialize Administrative Supabase Client
supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)


# 🛡️ SECURITY LAYER: TOKEN VERIFICATION UTILITIES
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
        return {"roll_number": roll_number, "name": payload.get("name"), "department": payload.get("dept")}
    except JWTError:
        raise credentials_exception


# -------------------------------------------------------------------------
# 1. CENTRALIZED AUTHENTICATION CONTROLLER (Replaces local client parsing)
# -------------------------------------------------------------------------
@app.post("/api/auth/login")
async def secure_login(payload: dict):
    roll_number = str(payload.get("roll_number", "")).strip()
    entered_password = str(payload.get("password", "")).strip() # Represents Student Date of Birth

    if not roll_number or not entered_password:
        raise HTTPException(status_code=400, detail="Missing required input credentials fields.")

    # Query administrative layer using raw SQL structure logic to find matching record indexes
    response = supabase.table("StudentDetails").select("*").eq("Roll_No", roll_number).maybe_single().execute()
    student = response.data

    if not student:
        # Secondary fallback lookup mapping parameter parsing patterns
        parsed_roll = int(roll_number) if roll_number.isdigit() else None
        if parsed_roll:
            response = supabase.table("StudentDetails").select("*").eq("Roll_No", parsed_roll).maybe_single().execute()
            student = response.data

    if not student:
        raise HTTPException(status_code=404, detail="No matching student record workspace registered.")

    # Normalize target password parameters across expected database table layout definitions
    correct_dob = str(student.get("dob") or student.get("DOB") or student.get("Date_of_Birth") or "").strip()
    
    clean_entered = "".join(filter(str.isdigit, entered_password))
    clean_correct = "".join(filter(str.isdigit, correct_dob))

    if clean_entered != clean_correct and entered_password != correct_dob:
        raise HTTPException(status_code=401, detail="Invalid date of birth password parameters.")

    # Issue Secure Server-Signed JWT Access Credentials back to the device layout environment
    token_data = {
        "sub": str(student.get("Roll_No")),
        "name": student.get("Name", "Student"),
        "dept": student.get("Programme") or student.get("department")
    }
    jwt_token = create_access_token(token_data)

    return {
        "access_token": jwt_token,
        "token_type": "bearer",
        "user": {
            "id": str(student.get("Roll_No")),
            "name": student.get("Name"),
            "roll_number": str(student.get("Roll_No")),
            "email": student.get("Email"),
            "department": student.get("Programme") or student.get("department"),
            "semester": student.get("Semester", "4"),
            "dob": correct_dob
        }
    }


# -------------------------------------------------------------------------
# 2. DOCUMENT VAULT MANAGEMENT PIPELINE (Per-user sandboxing)
# -------------------------------------------------------------------------
@app.post("/api/vault/upload")
async def vault_upload_pipeline(
    token: str = Form(...),
    file: UploadFile = File(...)
):
    user = await get_current_user(token)
    
    # Securely stream files straight from backend routing parameters directly to Telegram API boundaries
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

    # Write entry transaction safely down to SQLite/Supabase index layers via centralized server rules
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
    # Strictly sandbox database queries based on JWT session validation parameters
    response = supabase.table("student_vault").select("*").eq("user_id", user["roll_number"]).execute()
    return response.data


# -------------------------------------------------------------------------
# 3. CHAT ROOM MIDDLEWARE ROUTER & DISPATCHER
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
    
    # Save directly to centralized collection pools
    db_response = supabase.table("GroupChats").insert(chat_entry).execute()
    
    # Trigger background tasks to target external Firebase channels synchronously
    return {"success": True, "data": db_response.data}


# -------------------------------------------------------------------------
# 4. ACADEMIC SCHEDULES & TIMETABLE RESOURCE DELIVERY ENGINE
# -------------------------------------------------------------------------
@app.get("/api/schedule/fetch")
async def fetch_academic_schedules(department: str, semester: str):
    # Route structured schedule logs from isolated system storage layers smoothly
    response = supabase.table("AcademicSchedules")\
        .select("*")\
        .eq("department", department)\
        .eq("semester", semester)\
        .execute()
    return response.data


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)