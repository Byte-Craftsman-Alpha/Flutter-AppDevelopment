import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'attendance_db_service.dart';
import 'auth_service.dart';

class CloudSyncService {
  static bool isOnline = false;

  static Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('${AuthService.apiBaseUrl}$path').replace(queryParameters: query);
  }

  static Future<bool> heartbeat() async {
    final token = await AuthService.getAuthToken();
    if (token == null || token.isEmpty) return false;
    try {
      final deviceId = await AuthService.getDeviceId();
      final response = await http
          .post(
            _uri('/api/auth/heartbeat', {'token': token}),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'device_id': deviceId}),
          )
          .timeout(const Duration(seconds: 8));
      isOnline = response.statusCode == 200;
      return isOnline;
    } on SocketException catch (_) {
      isOnline = false;
      return false;
    } on TimeoutException catch (_) {
      isOnline = false;
      return false;
    } catch (_) {
      isOnline = false;
      return false;
    }
  }

  static Future<void> logoutDevice() async {
    final token = await AuthService.getAuthToken();
    if (token == null || token.isEmpty) return;
    try {
      final deviceId = await AuthService.getDeviceId();
      await http
          .post(
            _uri('/api/auth/logout', {'token': token}),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'device_id': deviceId}),
          )
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  static Future<bool> bootstrapFromCloud() async {
    final token = await AuthService.getAuthToken();
    if (token == null || token.isEmpty) return false;
    try {
      final response = await http
          .get(_uri('/api/sync/bootstrap', {'token': token}))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        isOnline = false;
        return false;
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      final group = data['subscribed_schedule_group']?.toString();
      if (group != null && group.isNotEmpty) {
        await AuthService.saveSubscribedSchedule(group);
      } else {
        await AuthService.clearSubscribedSchedule();
      }

      final tasks = data['tasks'];
      if (tasks is List) {
        final prefs = await SharedPreferences.getInstance();
        final roll = AuthService.currentUser?.rollNumber ?? 'default';
        await prefs.setString('offline_tasks_$roll', jsonEncode(tasks));
      }

      final attendance = data['attendance'];
      if (attendance is List) {
        await AttendanceDbService.replaceAllAttendanceRecords(
          attendance.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        );
      }

      isOnline = true;
      return true;
    } on SocketException catch (_) {
      isOnline = false;
      return false;
    } on TimeoutException catch (_) {
      isOnline = false;
      return false;
    } catch (_) {
      isOnline = false;
      return false;
    }
  }

  static Future<bool> pushState({List<Map<String, dynamic>>? tasks}) async {
    final token = await AuthService.getAuthToken();
    if (token == null || token.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final roll = AuthService.currentUser?.rollNumber ?? 'default';
      final localTasks = tasks ??
          ((jsonDecode(prefs.getString('offline_tasks_$roll') ?? '[]') as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList());
      final attendance = await AttendanceDbService.getAllAttendanceRecords();
      final response = await http
          .post(
            _uri('/api/sync/state', {'token': token}),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'tasks': localTasks, 'attendance': attendance}),
          )
          .timeout(const Duration(seconds: 12));
      isOnline = response.statusCode == 200;
      return isOnline;
    } catch (_) {
      isOnline = false;
      return false;
    }
  }

  static Future<bool> updateScheduleSubscription(String? groupName) async {
    final token = await AuthService.getAuthToken();
    if (token == null || token.isEmpty) return false;
    try {
      final response = await http
          .post(
            _uri('/api/user/schedule-subscription', {'token': token}),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'group_name': groupName ?? ''}),
          )
          .timeout(const Duration(seconds: 10));
      isOnline = response.statusCode == 200;
      return isOnline;
    } catch (_) {
      isOnline = false;
      return false;
    }
  }
}
