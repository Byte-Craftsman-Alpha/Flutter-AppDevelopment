import os
import json
import httpx
from typing import Optional, List, Dict, Any
from datetime import datetime, timedelta
from fastapi import FastAPI, Depends, HTTPException, status, File, UploadFile, Form
from fastapi.middleware.cors import CORSMiddleware
from supabase import create_client, Client
from jose import JWTError, jwt

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

def get_field_insensitive(data: Dict[str, Any], target_keys: List[String], default_val: str = "") -> str:
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
# 1. CENTRALIZED AUTHENTICATION CONTROLLER (Robust Version-Safe Matching)
# -------------------------------------------------------------------------
@app.post("/api/auth/login")
async def secure_login(payload: dict):
    roll_number = str(payload.get("roll_number", "")).strip()
    entered_password = str(payload.get("password", "")).strip()  # Represents Student Date of Birth

    if not roll_number or not entered_password:
        raise HTTPException(status_code=400, detail="Missing required input credentials fields.")

    # 💡 OPTIMIZATION: Replaced non-standard .maybe_single() with standard list slice for cross-version compatibility
    response = supabase.table("StudentDetails").select("*").eq("Roll_No", roll_number).execute()
    student = response.data[0] if response.data else None

    if not student:
        # Secondary fallback lookup mapping parameter parsing patterns
        parsed_roll = int(roll_number) if roll_number.isdigit() else None
        if parsed_roll:
            response = supabase.table("StudentDetails").select("*").eq("Roll_No", parsed_roll).execute()
            student = response.data[0] if response.data else None

    if not student:
        raise HTTPException(status_code=404, detail="No matching student record workspace registered.")

    # 💡 Robust, Case-Insensitive key retrieval for Date of Birth field parameters
    correct_dob = get_field_insensitive(
        student, 
        ["dob", "date_of_birth"], 
        default_val=""
    )

    if not correct_dob:
        raise HTTPException(status_code=500, detail="Date of Birth data schema column missing in database mapping.")

    # 💡 Normalize both passwords by stripping non-numeric characters (hyphens, slashes, spaces)
    clean_entered = "".join(filter(str.isdigit, entered_password))
    clean_correct = "".join(filter(str.isdigit, correct_dob))

    # Support fallback to direct string comparison if digit cleaning yields empty outcomes
    is_match = (clean_entered == clean_correct and clean_entered != "") or (entered_password == correct_dob)

    if not is_match:
        raise HTTPException(status_code=401, detail="Invalid date of birth password parameters.")

    # 💡 Case-Insensitive Extraction for User Properties Mapping
    student_name = get_field_insensitive(student, ["name"], "Student")
    student_roll = get_field_insensitive(student, ["roll_no", "roll_number", "roll_no."], roll_number)
    student_email = get_field_insensitive(student, ["email"])
    student_programme = get_field_insensitive(student, ["programme", "department", "dept", "branch"])
    student_semester = get_field_insensitive(student, ["semester"], "4")

    # Issue Secure Server-Signed JWT Access Credentials back to the device layout environment
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
            # Additional optional metrics for dynamic user mapping details
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
# 4. ACADEMIC SCHEDULES & TIMETABLE RESOURCE DELIVERY ENGINE (Upgraded)
# -------------------------------------------------------------------------
@app.get("/api/schedule/fetch")
async def fetch_academic_schedules(department: str, semester: str, group_name: Optional[str] = None):
    # Handle both explicit department checks and calendar event bypass blocks seamlessly
    if department == "Calendar" and semester == "Events":
        response = supabase.table("Monthly Calendar").select("*").execute()
        return response.data

    # Fetch all weekly schedules to perform case-insensitive and column-insensitive filtering in memory.
    # This completely shields the synchronization pipeline from PostgreSQL structural and casing variations.
    response = supabase.table("Weekly Schedules").select("*").execute()
    all_schedules = response.data or []

    # 💡 1. Prioritize strict matching by group_name (ScheduleGroupName) if provided by the client
    if group_name:
        matched_by_group = []
        for row in all_schedules:
            row_group = get_field_insensitive(
                row, 
                ["schedulegroupname", "schedule_group_name", "group_name", "group"]
            )
            if row_group.lower() == group_name.lower():
                matched_by_group.append(row)
        
        if matched_by_group:
            return matched_by_group

    # 💡 2. Fallback: Filter by department and semester case-insensitively
    matched_by_filters = []
    for row in all_schedules:
        row_dept = get_field_insensitive(
            row, 
            ["department", "programme", "dept", "branch", "course"]
        )
        row_sem = get_field_insensitive(
            row, 
            ["semester", "sem"]
        )
        
        if row_dept.lower() == department.lower() and row_sem.lower() == semester.lower():
            matched_by_filters.append(row)

    return matched_by_filters

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)