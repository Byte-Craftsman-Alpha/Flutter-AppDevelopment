import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class AuthService {
  static const String _userSessionKey = 'user_session_data';
  static const String _scheduleGroupKey = 'subscribed_schedule_group';
  static const String _jwtTokenKey = 'jwt_auth_token'; // 💡 Secure store key for FastAPI JWT token
  
  // 💡 Global Static Variables: Accessible from ANY screen/file in your app
  // E.g., AuthService.currentUser?.name or AuthService.jwtToken
  static UserModel? currentUser;
  static String? jwtToken; // 💡 Locally cached JWT Token for lightning-fast lookups

  // 💡 Load the persistent user object and JWT token from storage on app boot
  static Future<bool> loadSession() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? userJson = prefs.getString(_userSessionKey);
    final String? token = prefs.getString(_jwtTokenKey);
    
    if (userJson != null && token != null) {
      try {
        currentUser = UserModel.fromJson(userJson);
        jwtToken = token;
        return true; 
      } catch (e) {
        // Clear corrupt session indices cleanly
        await prefs.remove(_userSessionKey);
        await prefs.remove(_jwtTokenKey);
        currentUser = null;
        jwtToken = null;
      }
    }
    return false; 
  }

  // 💡 Save the parsed UserModel and optional JWT token permanently to the phone disk
  static Future<void> saveSession(UserModel user, {String? token}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userSessionKey, user.toJson());
    currentUser = user; 
    
    if (token != null) {
      await prefs.setString(_jwtTokenKey, token);
      jwtToken = token;
    }
  }

  // 💡 Read the persisted or cached JWT token from local storage
  static Future<String?> getAuthToken() async {
    if (jwtToken != null) return jwtToken;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    jwtToken = prefs.getString(_jwtTokenKey);
    return jwtToken;
  }

  // 💡 Persist the selected schedule group name (e.g., "B.Tech (IT) 2024-28 [A]")
  static Future<void> saveSubscribedSchedule(String groupName) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scheduleGroupKey, groupName);
  }

  // 💡 Read the persisted schedule group from local storage
  static Future<String?> getSubscribedSchedule() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_scheduleGroupKey);
  }

  // 💡 Clear memory and delete all saved data on logout
  static Future<void> clearSession() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userSessionKey);
    await prefs.remove(_jwtTokenKey); // Wipe JWT authentication key
    await prefs.remove(_scheduleGroupKey); // Wipe schedule preference on sign out
    currentUser = null; 
    jwtToken = null;
  }

  // 💡 Helper check method: Verified both user data and backend security credentials are valid
  static bool get isLoggedIn => currentUser != null && jwtToken != null;
}