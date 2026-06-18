import firebase_admin
from firebase_admin import credentials, messaging
from dotenv import load_dotenv
import os

load_dotenv()

# 💡 Initialize Firebase Admin (Do this near the top of app.py)
# Point this to the JSON file you downloaded from Firebase Service Accounts
cred = credentials.Certificate(
    {
        "type": os.environ.get("type"),
        "project_id": os.environ.get("project_id"),
        "private_key_id": os.environ.get("private_key_id"),
        "private_key": os.environ.get("private_key","").replace('\\n', '\n'),
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

# ... your other FastAPI code ...

def send_push_notification(title: str, body: str, target_device_token: str):
    # Construct the notification payload
    message = messaging.Message(
        notification=messaging.Notification(
            title=title,
            body=body,
        ),
        # You can also pass hidden data to the app here
        data={"click_action": "FLUTTER_NOTIFICATION_CLICK", "type": "chat_alert"},
        token=target_device_token, # The specific phone to send to
    )

    # Fire it off to Firebase
    response = messaging.send(message)
    
    return {"success": True, "message_id": response}

def broadcast_notification(title: str, body: str, topic: str):
    try:
        # Construct the message targeting a topic with high-priority settings
        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            topic=topic,
            
            # --- ANDROID CONFIGURATION ---
            android=messaging.AndroidConfig(
                priority='high' # Forces immediate delivery and wakes sleeping devices
            ),
            
            # --- APPLE (iOS) CONFIGURATION ---
            apns=messaging.APNSConfig(
                headers={
                    'apns-priority': '10', # '10' means send immediately. '5' is for background.
                },
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        sound='default', # Ensures it triggers an alert
                    )
                )
            )
        )

        response = messaging.send(message)
        return {"success": True, "message_id": response}
    
    except Exception as e:
        print(f"Error sending message: {e}")
        return {"success": False, "error": str(e)}

# print("Push notification function is ready to use!")
# send_push_notification("Hello from FastAPI!", "This is a test notification.", "your_device_token_here")
print(broadcast_notification("A test notification", "How is you day man??", 'general'))