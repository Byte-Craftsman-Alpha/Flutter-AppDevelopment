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
        "private_key": os.environ.get("private_key","").replace('\n', '\n'),
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

def send_card_background_update(
    image_url: str, 
    expiry_time: str, 
    target_device_token: str = None, 
    topic: str = None
):
    """
    Sends a silent data-only push notification to trigger the dynamic background 
    downloader on the Flutter app.
    
    :param image_url: Public URL of the image to download.
    :param expiry_time: ISO 8601 timestamp (e.g. "2026-06-25T15:30:00Z") OR remaining duration in seconds (e.g. "3600")
    :param target_device_token: Token of a specific target device (optional)
    :param topic: FCM topic to broadcast to (optional)
    """
    try:
        # Crucial: All keys and values in the 'data' payload MUST be strings
        data_payload = {
            "image_url": str(image_url),
            "expiry_time": str(expiry_time)
        }
        
        # --- ANDROID CONFIGURATION ---
        # Wakes up sleeping/dozed Android devices immediately to process in background
        android_config = messaging.AndroidConfig(
            priority="high"
        )
        
        # --- APPLE (iOS) CONFIGURATION ---
        # Required headers & payloads to ensure iOS wakes the app in background
        apns_config = messaging.APNSConfig(
            headers={
                "apns-priority": "5",            # '5' is mandatory for silent / background updates on iOS
                "apns-push-type": "background"    # Required by Apple for silent background tasks
            },
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    content_available=True,       # Crucial: Wakes up iOS App background runner
                )
            )
        )
        
        # Assemble message (Omit 'notification' block entirely to keep it silent)
        message = messaging.Message(
            data=data_payload,
            token=target_device_token,
            topic=topic,
            android=android_config,
            apns=apns_config
        )
        
        # Fire it off
        response = messaging.send(message)
        return {"success": True, "message_id": response}
        
    except Exception as e:
        print(f"Error sending silent push: {e}")
        return {"success": False, "error": str(e)}

# print("Push notification function is ready to use!")
# send_push_notification("Hello from FastAPI!", "This is a test notification.", "your_device_token_here")
# print(broadcast_notification("A test notification", "How is you day man??", 'general'))
# Wipes off and reverts to default after 10800 seconds (3 hours)
send_card_background_update(
    image_url="https://imgs.search.brave.com/HRxptjCm63gNvAzaUoMMvc9IIPkn1y6D7BktbxHxUKw/rs:fit:860:0:0:0/g:ce/aHR0cHM6Ly9zdGF0/aWMudmVjdGVlenku/Y29tL3N5c3RlbS9y/ZXNvdXJjZXMvdGh1/bWJuYWlscy8wMDYv/OTI5LzY4Mi9zbWFs/bC9hYnN0cmFjdC1i/YWNrZ3JvdW5kLWJv/a2VoLWNpcmNsZS1s/aWdodC1vcmFuZ2Ut/YWJzdHJhY3Qtb3Jh/bmdlLWVmZmVjdC1i/YWNrZ3JvdW5kLWxp/Z2h0LW9yYW5nZS1h/YnN0cmFjdC1iYWNr/Z3JvdW5kLWZyZWUt/cGhvdG8uanBn",
    expiry_time="10", # 3 hours in seconds
    topic="general"
)