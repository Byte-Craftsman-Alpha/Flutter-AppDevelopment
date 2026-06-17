import 'dart:convert'; // Required for parsing notification payloads
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'constants/design_system.dart'; 
import 'services/auth_wrapper.dart';
import 'services/auth_service.dart';
import 'constants/theme.dart'; 

// 💡 Globals for notifications and context-less routing
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 💡 GLOBAL HELPERS: Call these from ANY file simply by importing main.dart!
Future<void> subscribeNotificationTopic(String topic) async {
  if (topic.isEmpty) return;
  // Firebase topics cannot contain spaces or special symbols, so we sanitize it automatically
  String sanitizedTopic = topic.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '_');
  await FirebaseMessaging.instance.subscribeToTopic(sanitizedTopic);
  debugPrint("✅ Subscribed to topic: $sanitizedTopic");
}

Future<void> unsubscribeNotificationTopic(String topic) async {
  if (topic.isEmpty) return;
  String sanitizedTopic = topic.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '_');
  await FirebaseMessaging.instance.unsubscribeFromTopic(sanitizedTopic);
  debugPrint("🚫 Unsubscribed from topic: $sanitizedTopic");
}

Future<void> unsubscribeFromAllTopics() async {
  try {
    // FCM does not have a native 'unsubscribe from all' method.
    // Deleting the token completely wipes all active topic subscriptions linked to this device.
    await FirebaseMessaging.instance.deleteToken();
    
    // Immediately request a new token so the app can still receive direct notifications.
    String? newToken = await FirebaseMessaging.instance.getToken();
    debugPrint("🚫 Unsubscribed from ALL topics successfully. New FCM Token generated: $newToken");
  } catch (e) {
    debugPrint("❌ Error unsubscribing from all topics: $e");
  }
}

// 💡 TOP-LEVEL FUNCTION: Handles notifications when the app is completely closed.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  
  // Initialize the plugin inside the background handler to guarantee execution
  const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings = InitializationSettings(android: androidSettings);
  
  await flutterLocalNotificationsPlugin.initialize(
    settings: initSettings,
  );

  // Manually show the notification so it always appears in the system tray
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'group_chat_channel',
    'EduPortal Notifications',
    channelDescription: 'Real-time university alerts and group chats',
    importance: Importance.max,
    priority: Priority.high,
  );
  
  await flutterLocalNotificationsPlugin.show(
    id: message.hashCode,
    title: message.data['title'] ?? 'New Alert',
    body: message.data['body'] ?? 'You have a new message.',
    notificationDetails: const NotificationDetails(android: androidDetails),
    // Pass the entire data object as a JSON payload for routing later
    payload: jsonEncode(message.data),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://kvuvxoajuenszfdanoif.supabase.co',
    publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt2dXZ4b2FqdWVuc3pmZGFub2lmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTU2MjA5NiwiZXhwIjoyMDkxMTM4MDk2fQ.9v882ryLmBv-Laoe8b1WHxfGCwBHe1VY1ufmbId9xjI',
  );

  await AuthService.loadSession();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  @override
  void initState() {
    super.initState();
    _setupPushNotifications();
    _checkInitialNotification();
  }

  // 💡 Check if the app was launched FROM a notification tap when it was fully closed
  Future<void> _checkInitialNotification() async {
    // 1. Check for Local Notification launch (from background handler)
    final NotificationAppLaunchDetails? details = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if (details != null && details.didNotificationLaunchApp && details.notificationResponse?.payload != null) {
      _handleNotificationRouting(details.notificationResponse!.payload!);
    }

    // 2. Check for direct FCM launch (Fallback)
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationRouting(jsonEncode(initialMessage.data));
    }
  }

  Future<void> _setupPushNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('🔔 User granted permission');
      
      String? token = await messaging.getToken();
      debugPrint('📱 Device FCM Token: $token');

      // 💡 Initialize Local Notifications for foreground/background taps
      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('launcher_icon');
      const InitializationSettings initSettings = InitializationSettings(android: androidSettings);
      
      await flutterLocalNotificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          if (response.payload != null) {
            _handleNotificationRouting(response.payload!);
          }
        },
      );

      // Listen for messages while app is currently open
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📩 Foreground Message Received: ${message.data['title']}');
        
        const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
          'group_chat_channel',
          'EduPortal Notifications',
          importance: Importance.max,
          priority: Priority.high,
          // 💡 FIXED: Explicitly force the notification channel to use your launcher icon
          icon: 'launcher_icon',
        );

        flutterLocalNotificationsPlugin.show(
          id: message.hashCode,
          title: message.data['title'] ?? 'New Alert',
          body: message.data['body'] ?? 'You have a new message.',
          notificationDetails: const NotificationDetails(android: androidDetails),
          payload: jsonEncode(message.data),
        );
      });

      // Listen for taps when app is in the background (but still alive in memory)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleNotificationRouting(jsonEncode(message.data));
      });
    }
  }

  // 💡 Global Routing Logic
  void _handleNotificationRouting(String payloadStr) {
    try {
      final Map<String, dynamic> data = jsonDecode(payloadStr);
      final targetRoute = data['target_page']; // e.g. "/chat" or "/vault" sent from your FastAPI
      
      if (targetRoute != null && targetRoute.toString().isNotEmpty) {
        // Navigate after the first frame has rendered safely
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navigatorKey.currentState?.pushNamed(targetRoute.toString());
        });
      }
    } catch (e) {
      debugPrint("Routing Parse Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // 💡 Link the global navigator key
      title: 'EduPortal',
      debugShowCheckedModeBanner: false,
      theme: EduTheme.lightTheme, 
      darkTheme: EduTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const AuthWrapper(),
      
      // 💡 Define target routes here for your deep-linking to work!
      routes: {
        // '/chat': (context) => ChatGroupPage(currentUserId: AuthService.currentUser?.rollNumber ?? ''),
        // '/vault': (context) => VaultPage(currentUserId: AuthService.currentUser?.rollNumber ?? ''),
      },
    );
  }
}