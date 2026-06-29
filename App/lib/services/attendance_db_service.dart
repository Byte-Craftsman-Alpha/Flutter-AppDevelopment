import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'auth_service.dart';

class AttendanceDbService {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  static Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    // 💡 Bumped version to v4 to ensure a fresh schema on existing devices
    final path = join(dbPath, 'attendance_tracker_v4.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE attendance (
            id TEXT PRIMARY KEY, date TEXT, time_slot TEXT, subject TEXT, status TEXT
          )
        ''');
      },
    );
  }

  /// 💡 Pushes all local SQLite data to Cloud JSONB asynchronously
  static Future<void> _triggerCloudSync() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> records = await db.query('attendance');
      
      // Convert flat table to highly structured JSON map
      final Map<String, dynamic> jsonbPayload = {};
      for (var r in records) {
        final date = r['date'];
        final key = "${r['time_slot']}|${r['subject']}";
        if (!jsonbPayload.containsKey(date)) jsonbPayload[date] = {};
        jsonbPayload[date][key] = r['status'];
      }
      
      final token = await AuthService.getAuthToken();
      if (token == null) return;
      
      await http.post(
        Uri.parse('https://flutter-app-development-mu.vercel.app/api/sync/cloud-data'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token, 'attendance': jsonbPayload}),
      );
    } catch (_) {}
  }

  /// 💡 Restores Data from JSONB Cloud on new device login
  static Future<void> syncFromCloud() async {
    try {
      final token = await AuthService.getAuthToken();
      if (token == null) return;

      final res = await http.get(Uri.parse('https://flutter-app-development-mu.vercel.app/api/sync/cloud-data?token=$token'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body)['data'];
        final Map<String, dynamic> attendanceJsonb = data['attendance_jsonb'] ?? {};
        
        final db = await database;
        await db.transaction((txn) async {
          await txn.delete('attendance'); // Clear local cache to prevent ghost data
          for (var date in attendanceJsonb.keys) {
            final classes = attendanceJsonb[date] as Map<String, dynamic>;
            for (var classKey in classes.keys) {
              final parts = classKey.split('|');
              if (parts.length == 2) {
                final id = "${date}_${parts[0].replaceAll(' ', '')}_${parts[1].replaceAll(' ', '')}";
                await txn.insert('attendance', {
                  'id': id, 'date': date, 'time_slot': parts[0], 'subject': parts[1], 'status': classes[classKey]
                }, conflictAlgorithm: ConflictAlgorithm.replace);
              }
            }
          }
        });
      }
    } catch (_) {}
  }

  static Future<void> logAttendance({
    required String date, required String timeSlot, required String subject, required String status,
  }) async {
    final db = await database;
    final id = "${date}_${timeSlot.replaceAll(' ', '')}_${subject.replaceAll(' ', '')}";

    if (status == 'none') {
      await db.delete('attendance', where: 'id = ?', whereArgs: [id]);
    } else {
      await db.insert(
        'attendance',
        {'id': id, 'date': date, 'time_slot': timeSlot, 'subject': subject, 'status': status},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    _triggerCloudSync(); // Fire and forget remote sync
  }

  static Future<Map<String, String>> getDateAttendance(String date) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('attendance', where: 'date = ?', whereArgs: [date]);
    return { for (var item in maps) "${item['time_slot']}|${item['subject']}": item['status'].toString() };
  }

  static Future<Map<String, Map<String, String>>> getWeeklyAttendance(List<String> dates) async {
    if (dates.isEmpty) return {};
    final db = await database;
    final String placeholders = List.filled(dates.length, '?').join(',');
    final List<Map<String, dynamic>> maps = await db.query('attendance', where: 'date IN ($placeholders)', whereArgs: dates);

    final Map<String, Map<String, String>> weeklyLog = { for (var date in dates) date: {} };
    for (var item in maps) {
      weeklyLog[item['date'].toString()]?["${item['time_slot']}|${item['subject']}"] = item['status'].toString();
    }
    return weeklyLog;
  }

  static Future<double> calculateAttendancePercentage() async {
    final db = await database;
    final List<Map<String, dynamic>> records = await db.query('attendance', where: "status = 'attended' OR status = 'missed'");
    if (records.isEmpty) return 100.0;
    return (records.where((r) => r['status'] == 'attended').length / records.length) * 100.0;
  }
}
