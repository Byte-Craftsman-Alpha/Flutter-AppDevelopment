import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'constants/design_system.dart'; 
import 'services/auth_wrapper.dart';
import 'services/auth_service.dart';
import 'constants/theme.dart'; 
import 'pages/home.dart'; // 💡 IMPORT MYHOMEPAGE TO ACCESS BACKGROUND SERVICES

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
    String? newToken = await FirebaseMessaging.instance.getToken();
    debugPrint("🚫 Unsubscribed from ALL topics successfully. New FCM Token generated: $newToken");
  } catch (e) {
    debugPrint("❌ Error unsubscribing from all topics: $e");
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  
  // 💡 SILENT NOTIFICATION ROUTING CHECK (BACKGROUND STATE)
  // If the push message contains card background updating data, execute it directly and exit.
  if (message.data.containsKey('image_url')) {
    await BackgroundCardBgService.processSilentNotification(message.data);
    return; // Prevent triggering any noisy generic notification alerts!
  }

  const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings = InitializationSettings(android: androidSettings);
  
  await flutterLocalNotificationsPlugin.initialize(
    settings: initSettings,
  );

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'group_chat_channel',
    'EduPortal Notifications',
    channelDescription: 'Real-time university alerts and group chats',
    importance: Importance.max,
    priority: Priority.high,
  );
  
  await flutterLocalNotificationsPlugin.show(
    id: message.hashCode,
    title: message.notification?.title ?? message.data['title'] ?? 'New Alert',
    body: message.notification?.body ?? message.data['body'] ?? 'You have a new message.',
    notificationDetails: const NotificationDetails(android: androidDetails),
    payload: jsonEncode(message.data),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

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

  Future<void> _checkInitialNotification() async {
    final NotificationAppLaunchDetails? details = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if (details != null && details.didNotificationLaunchApp && details.notificationResponse?.payload != null) {
      _handleNotificationRouting(details.notificationResponse!.payload!);
    }

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

      await subscribeNotificationTopic("general");

      // subscribe to the roll number
      await subscribeNotificationTopic((AuthService.currentUser?.rollNumber).toString());

      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
      );
      
      await flutterLocalNotificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          if (response.payload != null) {
            _handleNotificationRouting(response.payload!);
          }
        },
      );

      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        debugPrint('📩 Foreground Message Received: ${message.notification?.title}');
        
        // 💡 SILENT NOTIFICATION ROUTING CHECK (FOREGROUND STATE)
        // If the push message contains card background updating data, execute it directly and exit.
        if (message.data.containsKey('image_url')) {
          await BackgroundCardBgService.processSilentNotification(message.data);
          return; // Processed silently, skip displaying noisy generic local notifications!
        }

        const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
          'group_chat_channel',
          'EduPortal Notifications',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        );

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
      routes: {
        // '/chat': (context) => ChatGroupPage(currentUserId: AuthService.currentUser?.rollNumber ?? ''),
        // '/vault': (context) => VaultPage(currentUserId: AuthService.currentUser?.rollNumber ?? ''),
      },
    );
  }
}