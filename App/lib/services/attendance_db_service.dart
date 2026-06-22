import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AttendanceDbService {
  static Database? _database;

  /// Returns the global thread-safe singleton SQLite database reference.
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  /// Initializes the SQLite database and sets up the primary schema.
  static Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'attendance_tracker_v3.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE attendance (
            id TEXT PRIMARY KEY,
            date TEXT,
            time_slot TEXT,
            subject TEXT,
            status TEXT
          )
        ''');
      },
    );
  }

  /// Logs or updates the status of a specific class instance on a given date.
  /// Status values can be: 'attended', 'missed', 'cancelled', 'holiday', or 'none' (resets status).
  static Future<void> logAttendance({
    required String date,
    required String timeSlot,
    required String subject,
    required String status,
  }) async {
    final db = await database;
    // Generate a unique token for the class instance to prevent overlaps in same-time slots across different days.
    final id = "${date}_${timeSlot.replaceAll(' ', '')}_${subject.replaceAll(' ', '')}";

    if (status == 'none') {
      await db.delete('attendance', where: 'id = ?', whereArgs: [id]);
    } else {
      await db.insert(
        'attendance',
        {
          'id': id,
          'date': date,
          'time_slot': timeSlot,
          'subject': subject,
          'status': status,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Retrieves log records mapped by "time_slot|subject" for a specific date.
  static Future<Map<String, String>> getDateAttendance(String date) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'attendance',
      where: 'date = ?',
      whereArgs: [date],
    );

    return {
      for (var item in maps) "${item['time_slot']}|${item['subject']}": item['status'].toString()
    };
  }

  /// Retrieves multi-date logs for the full week page view to prevent nested queries.
  static Future<Map<String, Map<String, String>>> getWeeklyAttendance(List<String> dates) async {
    if (dates.isEmpty) return {};
    final db = await database;
    final String placeholders = List.filled(dates.length, '?').join(',');
    
    final List<Map<String, dynamic>> maps = await db.query(
      'attendance',
      where: 'date IN ($placeholders)',
      whereArgs: dates,
    );

    final Map<String, Map<String, String>> weeklyLog = {};
    for (var date in dates) {
      weeklyLog[date] = {};
    }

    for (var item in maps) {
      final date = item['date'].toString();
      final key = "${item['time_slot']}|${item['subject']}";
      weeklyLog[date]?[key] = item['status'].toString();
    }
    return weeklyLog;
  }

  /// Calculates the official percentage of classes attended.
  /// Standard academic compliance completely ignores cancelled or holiday events.
  static Future<double> calculateAttendancePercentage() async {
    final db = await database;
    final List<Map<String, dynamic>> records = await db.query(
      'attendance',
      where: "status = 'attended' OR status = 'missed'",
    );

    if (records.isEmpty) {
      return 100.0; // Return a perfect baseline representation for incoming semesters.
    }

    final int attended = records.where((r) => r['status'] == 'attended').length;
    return (attended / records.length) * 100.0;
  }
}