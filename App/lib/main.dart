import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'services/auth_wrapper.dart';
import 'services/auth_service.dart';
import 'constants/theme.dart'; 

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> subscribeNotificationTopic(String topic) async {
  if (topic.isEmpty) return;
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
    await FirebaseMessaging.instance.deleteToken();
    debugPrint("🧹 Cleared all Firebase Notification Topics.");
  } catch (e) {
    debugPrint("Error clearing topics: $e");
  }
}

/// Top-level background notification handler.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Silent push received in background: ${message.data}");
  // Removed the legacy BackgroundCardBgService reference
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  // Load User Session & Preferences
  await AuthService.loadSession();

  runApp(const EduPortalApp());
}

class EduPortalApp extends StatefulWidget {
  const EduPortalApp({super.key});

  @override
  State<EduPortalApp> createState() => _EduPortalAppState();
}

class _EduPortalAppState extends State<EduPortalApp> {
  @override
  void initState() {
    super.initState();
    _setupNotifications();
  }

  void _setupNotifications() async {
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidSettings);
    
    // Updated to use named parameter (initializationSettings)
    await flutterLocalNotificationsPlugin.initialize(
      settings: initSettings, 
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("Foreground message received: ${message.notification?.title}");
      
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'eduportal_alerts', 'EduPortal Alerts',
        importance: Importance.max,
        priority: Priority.high,
      );
      
      // Updated to use strict named parameters (id, title, body, notificationDetails, payload)
      flutterLocalNotificationsPlugin.show(
        id: message.hashCode,
        title: message.notification?.title ?? message.data['title'] ?? 'New Alert',
        body: message.notification?.body ?? message.data['body'] ?? 'You have a new message.',
        notificationDetails: const NotificationDetails(android: androidDetails),
        payload: jsonEncode(message.data),
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationRouting(jsonEncode(message.data));
    });
  }

  void _handleNotificationRouting(String payloadStr) {
    try {
      final Map<String, dynamic> data = jsonDecode(payloadStr);
      final targetRoute = data['target_page']; 
      
      if (targetRoute != null && targetRoute.toString().isNotEmpty) {
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
      navigatorKey: navigatorKey,
      title: 'EduPortal',
      debugShowCheckedModeBanner: false,
      theme: EduTheme.lightTheme, 
      darkTheme: EduTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const AuthWrapper(),
    );
  }
}