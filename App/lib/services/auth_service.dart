import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';

// 💡 Unified Global State Manager
class AppStateNotifier {
  static final ValueNotifier<int> globalRefreshNotifier = ValueNotifier(0);
  static final ValueNotifier<bool> isOnlineNotifier = ValueNotifier(true);
  
  static void triggerGlobalRefresh() {
    globalRefreshNotifier.value++;
  }
  
  static void setNetworkStatus(bool isOnline) {
    if (isOnlineNotifier.value != isOnline) {
      isOnlineNotifier.value = isOnline;
    }
  }
}

class AuthService {
  static const String _userSessionKey = 'user_session_data';
  static const String _scheduleGroupKey = 'subscribed_schedule_group';
  static const String _jwtTokenKey = 'jwt_auth_token';
  static const String _deviceIdKey = 'device_id_token';
  
  static UserModel? currentUser;
  static String? jwtToken;
  static String? _cachedDeviceId;

  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final prefs = await SharedPreferences.getInstance();
    _cachedDeviceId = prefs.getString(_deviceIdKey);
    if (_cachedDeviceId == null) {
      _cachedDeviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, _cachedDeviceId!);
    }
    return _cachedDeviceId!;
  }

  static Future<bool> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userSessionKey);
    final token = prefs.getString(_jwtTokenKey);
    
    if (userJson != null && token != null) {
      try {
        currentUser = UserModel.fromJson(userJson);
        jwtToken = token;
        return true; 
      } catch (_) {
        await clearSession();
      }
    }
    return false; 
  }

  static Future<void> saveSession(UserModel user, {String? token, String? cloudGroup}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userSessionKey, user.toJson());
    currentUser = user; 
    
    if (token != null) {
      await prefs.setString(_jwtTokenKey, token);
      jwtToken = token;
    }
    if (cloudGroup != null && cloudGroup.isNotEmpty) {
      await saveSubscribedSchedule(cloudGroup, syncToCloud: false);
    }
  }

  static Future<String?> getAuthToken() async => jwtToken;

  static Future<void> saveSubscribedSchedule(String groupName, {bool syncToCloud = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scheduleGroupKey, groupName);
    
    if (syncToCloud && jwtToken != null) {
      try {
        await http.post(
          Uri.parse('https://flutter-app-development-mu.vercel.app/api/user/update-group'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'token': jwtToken, 'group_name': groupName}),
        );
      } catch (_) {
        // Will sync next time online
      }
    }
  }

  static Future<String?> getSubscribedSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_scheduleGroupKey);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userSessionKey);
    await prefs.remove(_jwtTokenKey);
    await prefs.remove(_scheduleGroupKey);
    currentUser = null; 
    jwtToken = null;
  }

  static bool get isLoggedIn => currentUser != null && jwtToken != null;
}