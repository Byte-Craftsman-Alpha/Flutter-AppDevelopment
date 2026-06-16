import firebase_admin
from firebase_admin import credentials, messaging

# 💡 Initialize Firebase Admin (Do this near the top of app.py)
# Point this to the JSON file you downloaded from Firebase Service Accounts
cred = credentials.Certificate("./edu-portal-d0a62-firebase-adminsdk-fbsvc-c0b236157d.json")
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
        # Construct the message targeting a topic instead of a token
        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            topic=topic, # Firebase sends this to ALL devices subscribed to this topic
        )

        response = messaging.send(message)
        return {"success": True, "message_id": response}
    
    except Exception as e:
        print(e)

# print("Push notification function is ready to use!")
# send_push_notification("Hello from FastAPI!", "This is a test notification.", "your_device_token_here")
print(broadcast_notification("A test notification", "How is you day man??", 'general'))