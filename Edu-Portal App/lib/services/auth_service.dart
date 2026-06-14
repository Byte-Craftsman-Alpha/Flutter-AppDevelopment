import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class AuthService {
  static const String _userSessionKey = 'user_session_data';
  static const String _scheduleGroupKey = 'subscribed_schedule_group';
  
  // 💡 Global Static Variable: Accessible from ANY screen/file in your app
  // E.g., AuthService.currentUser?.name
  static UserModel? currentUser;

  // 💡 Load the persistent user object from storage on app boot
  static Future<bool> loadSession() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? userJson = prefs.getString(_userSessionKey);
    
    if (userJson != null) {
      try {
        currentUser = UserModel.fromJson(userJson);
        return true; 
      } catch (e) {
        // Clear corrupt data
        await prefs.remove(_userSessionKey);
        currentUser = null;
      }
    }
    return false; 
  }

  // 💡 Save the parsed UserModel permanently to the phone disk
  static Future<void> saveSession(UserModel user) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userSessionKey, user.toJson());
    currentUser = user; 
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
    await prefs.remove(_scheduleGroupKey); // Wipe schedule preference on sign out
    currentUser = null; 
  }

  // Helper check method
  static bool get isLoggedIn => currentUser != null;
}