import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../constants/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutty_solar_icons/flutty_solar_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../constants/theme.dart';
import '../services/auth_service.dart';
import '../services/crypto_service.dart';
import '../services/attendance_db_service.dart';
import '../services/cloud_sync_service.dart';

import 'ChatScreen.dart';
import 'CalendarScreen.dart';
import 'VaultScreen.dart';
import 'ProfileScreen.dart';

/// Top-level background notification handler.
/// Register this in your background message receiver service (e.g. Firebase Cloud Messaging onBackgroundMessage handler)
/// to instantly process card background changes even if the application is fully terminated.
@pragma('vm:entry-point')
Future<void> onSilentPushNotificationReceived(Map<String, dynamic> messageData) async {
  if (messageData.containsKey('image_url')) {
    await BackgroundCardBgService.processSilentNotification(messageData);
  }
}

/// Dynamic Persistent Storage & Resilient Background Downloader Service
class BackgroundCardBgService {
  static const String _keyActiveUrl = 'custom_bg_active_url';
  static const String _keyLocalPath = 'custom_bg_local_path';
  static const String _keyExpiry = 'custom_bg_expiry';
  static const String _keyStatus = 'custom_bg_download_status';

  static Future<void> processSilentNotification(Map<String, dynamic> payload) async {
    final String? imageUrl = payload['image_url']?.toString();
    final String? expiryStr = payload['expiry_time']?.toString(); // Supports ISO timestamp or remaining duration in seconds

    if (imageUrl == null || imageUrl.isEmpty) return;

    DateTime? expiry;
    if (expiryStr != null) {
      expiry = DateTime.tryParse(expiryStr);
      if (expiry == null) {
        final parsedInt = int.tryParse(expiryStr);
        if (parsedInt != null) {
          if (parsedInt > 100000000000) {
            expiry = DateTime.fromMillisecondsSinceEpoch(parsedInt);
          } else {
            expiry = DateTime.now().add(Duration(seconds: parsedInt));
          }
        }
      }
    }

    // Default expiry duration is 24 hours if unspecified
    expiry ??= DateTime.now().add(const Duration(hours: 24));

    if (expiry.isBefore(DateTime.now())) {
      await clearCustomBackground();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyExpiry, expiry.toIso8601String());

    final String? currentUrl = prefs.getString(_keyActiveUrl);
    final String? currentPath = prefs.getString(_keyLocalPath);

    // If new remote image url is pushed, reset and trigger progressive resilient download
    if (currentUrl != imageUrl || currentPath == null || !File(currentPath).existsSync()) {
      await prefs.setString(_keyActiveUrl, imageUrl);
      await prefs.setString(_keyStatus, 'downloading');
      
      // Perform background download task with exponential backoff retries
      _startBackgroundDownload(imageUrl);
    }
  }

  static Future<void> _startBackgroundDownload(String url) async {
    int retries = 5;
    int delaySeconds = 2;
    bool success = false;

    while (retries > 0 && !success) {
      try {
        success = await downloadImageResilient(url);
        if (success) break;
      } catch (e) {
        debugPrint("Background custom image download attempt failed: $e");
      }
      retries--;
      if (!success && retries > 0) {
        await Future.delayed(Duration(seconds: delaySeconds));
        delaySeconds *= 2; // Exponential backoff to avoid spamming user's data on slow networks
      }
    }

    final prefs = await SharedPreferences.getInstance();
    if (success) {
      await prefs.setString(_keyStatus, 'completed');
      // Trigger update globally across any active screens
      try {
        AppStateNotifier.scheduleRefreshNotifier.value = AppStateNotifier.scheduleRefreshNotifier.value + 1;
      } catch (_) {}
    } else {
      await prefs.setString(_keyStatus, 'failed');
    }
  }

  /// Implements range-resumable chunk downloading to avoid redundant data usage 
  /// and prevent rendering crashed or corrupted files on sudden connection drops.
  static Future<bool> downloadImageResilient(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      final directory = await getApplicationDocumentsDirectory();
      final filename = "custom_card_bg_${urlString.hashCode}.png";
      final finalFile = File("${directory.path}/$filename");
      final tempFile = File("${directory.path}/$filename.tmp");

      int existingLength = 0;
      if (tempFile.existsSync()) {
        existingLength = tempFile.lengthSync();
      }

      final client = http.Client();
      final request = http.Request('GET', uri);

      // Add Range header for partial resume if there's progressive cache
      if (existingLength > 0) {
        request.headers['Range'] = 'bytes=$existingLength-';
      }

      final response = await client.send(request);

      if (response.statusCode == 200 || response.statusCode == 206) {
        IOSink ioSink;
        if (response.statusCode == 206 && existingLength > 0) {
          ioSink = tempFile.openWrite(mode: FileMode.append);
        } else {
          // Range unsupported by remote server fallback - restart download safely
          ioSink = tempFile.openWrite(mode: FileMode.write);
          existingLength = 0;
        }

        final int totalLength = (response.contentLength ?? 0) + existingLength;
        int bytesDownloaded = existingLength;

        await response.stream.listen(
          (chunk) {
            ioSink.add(chunk);
            bytesDownloaded += chunk.length;
          },
          cancelOnError: true,
        ).asFuture();

        await ioSink.flush();
        await ioSink.close();

        // Check if the file matches specifications completely before applying to avoid crashes
        if (bytesDownloaded > 0 && (response.contentLength == null || bytesDownloaded == totalLength)) {
          if (finalFile.existsSync()) {
            finalFile.deleteSync();
          }
          tempFile.renameSync(finalFile.path);

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyLocalPath, finalFile.path);
          return true;
        } else {
          return false;
        }
      } else {
        return false;
      }
    } catch (e) {
      debugPrint("Resilient range download runtime exception: $e");
      return false;
    }
  }

  static Future<void> clearCustomBackground() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_keyLocalPath);
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
    await prefs.remove(_keyActiveUrl);
    await prefs.remove(_keyLocalPath);
    await prefs.remove(_keyExpiry);
    await prefs.remove(_keyStatus);
    
    try {
      AppStateNotifier.scheduleRefreshNotifier.value = AppStateNotifier.scheduleRefreshNotifier.value + 1;
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getActiveCustomBackground() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_keyLocalPath);
    final expiryStr = prefs.getString(_keyExpiry);

    if (path == null || expiryStr == null) return null;

    final expiry = DateTime.tryParse(expiryStr);
    if (expiry == null || expiry.isBefore(DateTime.now())) {
      await clearCustomBackground();
      return null;
    }

    final file = File(path);
    if (!file.existsSync()) return null;

    return {
      'path': path,
      'expiry': expiry,
    };
  }
}

class MyHomePage extends StatefulWidget {
  final String title;
  const MyHomePage({super.key, required this.title});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _hasSyncError = false;
  String _greeting = 'Welcome';

  List<Map<String, dynamic>> _todayClasses = [];
  List<Map<String, dynamic>> _todayEvents = [];
  List<Map<String, dynamic>> _recentVaultItems = [];

  // To-Do Reminders State
  List<Map<String, dynamic>> _reminders = [];
  final FlutterLocalNotificationsPlugin _localNotif = FlutterLocalNotificationsPlugin();

  // Attendance Tracker Cache State parameters
  Map<String, String> _todayAttendanceLog = {};
  double _attendancePercentage = 100.0;

  // Remote custom background status indicators
  String? _customBgImagePath;
  Timer? _expiryCheckTimer;
  Timer? _heartbeatTimer;
  bool _isOnline = false;

  int _parseTimeStr(String timeStr) {
    try {
      timeStr = timeStr.trim().toUpperCase();
      bool isPM = timeStr.contains('PM');
      bool isAM = timeStr.contains('AM');
      timeStr = timeStr.replaceAll('PM', '').replaceAll('AM', '').trim();
      final parts = timeStr.split(':');
      int hour = int.parse(parts[0]);
      int min = int.parse(parts[1]);
      if (isPM && hour != 12) hour += 12;
      if (isAM && hour == 12) hour = 0;
      return hour * 60 + min;
    } catch (_) {
      return 1440;
    }
  }

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones(); // Initialize timezone DB for background alarms
    _determineGreeting();
    _fetchDashboardContext();
    _loadAttendanceLogs();
    _loadCustomBackground(); // Verify custom remote background status on runtime initialization
    _refreshEverything(silent: true);

    // Properly chain the async setup so alarms don't try to sync before the plugin initializes
    _initNotificationsAndReminders();
    
    // Listen for schedule changes from ProfileScreen and CalendarScreen
    AppStateNotifier.scheduleRefreshNotifier.addListener(_onGlobalScheduleUpdate);

    // Periodic schedule checker for active background validity updates
    _expiryCheckTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      _checkBackgroundExpiration();
    });
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _refreshOnlineStatus();
    });
  }

  // Re-fetch local cache when the schedule has been updated across tabs
  void _onGlobalScheduleUpdate() {
    if (mounted) {
      _refreshEverything(silent: true);
      _loadAttendanceLogs();
      _loadCustomBackground(); // Instantly update active theme variations if background changes are hot-loaded
    }
  }

  Future<void> _refreshOnlineStatus() async {
    final online = await CloudSyncService.heartbeat();
    if (mounted) {
      setState(() => _isOnline = online);
    }
  }

  Future<void> _refreshEverything({bool silent = false}) async {
    final bootstrapped = await CloudSyncService.bootstrapFromCloud();
    if (mounted) {
      setState(() => _isOnline = bootstrapped || CloudSyncService.isOnline);
    }
    await _fetchDashboardContext(showError: !silent);
    await _loadAttendanceLogs();
    await _loadCustomBackground();
    await _loadReminders();
  }

  Future<void> _loadCustomBackground() async {
    final customBg = await BackgroundCardBgService.getActiveCustomBackground();
    if (mounted) {
      setState(() {
        _customBgImagePath = customBg?['path'];
      });
    }
  }

  Future<void> _checkBackgroundExpiration() async {
    if (_customBgImagePath != null) {
      final customBg = await BackgroundCardBgService.getActiveCustomBackground();
      if (customBg == null) {
        if (mounted) {
          setState(() {
            _customBgImagePath = null;
          });
        }
      }
    }
  }

  // Safely sequences the loading pipeline
  Future<void> _initNotificationsAndReminders() async {
    await _initializeLocalNotif();
    await _loadReminders();
  }

  @override
  void dispose() {
    _expiryCheckTimer?.cancel();
    _heartbeatTimer?.cancel();
    // Always unregister global listeners on memory disposal
    AppStateNotifier.scheduleRefreshNotifier.removeListener(_onGlobalScheduleUpdate);
    super.dispose();
  }

  void _determineGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      _greeting = 'Good Morning';
    } else if (hour < 17) {
      _greeting = 'Good Afternoon';
    } else {
      _greeting = 'Good Evening';
    }
  }

  String _formatDateToKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Future<void> _loadAttendanceLogs() async {
    final dateKey = _formatDateToKey(DateTime.now());
    final logs = await AttendanceDbService.getDateAttendance(dateKey);
    final percentage = await AttendanceDbService.calculateAttendancePercentage();
    if (mounted) {
      setState(() {
        _todayAttendanceLog = logs;
        _attendancePercentage = percentage;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SolarIcon(
              SolarIcons.DangerTriangle,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: EduDesignTokens.rose700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
        ),
      ),
    );
  }

  Future<void> _fetchDashboardContext({bool showError = true}) async {
    setState(() {
      _isLoading = true;
      _hasSyncError = false;
    });

    try {
      final token = await AuthService.getAuthToken();
      final groupName = await AuthService.getSubscribedSchedule() ?? '';

      final vaultUrl = Uri.parse(
        '${AuthService.apiBaseUrl}/api/vault/records?token=$token',
      );
      final vaultRes = await http
          .get(vaultUrl)
          .timeout(const Duration(seconds: 15));

      if (vaultRes.statusCode == 200) {
        final List<dynamic> records = json.decode(vaultRes.body);
        final List<Map<String, dynamic>> typedRecords = records
            .cast<Map<String, dynamic>>();

        typedRecords.sort((a, b) {
          final dateA =
              DateTime.tryParse(a['created_at'].toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final dateB =
              DateTime.tryParse(b['created_at'].toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return dateB.compareTo(dateA);
        });

        _recentVaultItems = typedRecords.take(4).toList();
      } else {
        throw Exception('Vault API rejected payload');
      }

      if (groupName.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        try {
          final user = AuthService.currentUser;
          final todayKey = _formatDateToKey(DateTime.now());
          final scheduleUrl = Uri.parse(
            '${AuthService.apiBaseUrl}/api/schedule/fetch'
            '?department=${Uri.encodeComponent(user?.department ?? '')}'
            '&semester=${Uri.encodeComponent(user?.semester ?? '4')}'
            '&group_name=${Uri.encodeComponent(groupName)}'
            '&date=${Uri.encodeComponent(todayKey)}',
          );
          final scheduleRes = await http.get(scheduleUrl).timeout(const Duration(seconds: 12));
          if (scheduleRes.statusCode == 200) {
            final List<dynamic> responseData = json.decode(scheduleRes.body);
            final scheduleRecord = responseData.isNotEmpty ? responseData.first : {};
            final List<dynamic> rawClassesList =
                scheduleRecord['ScheduleLists'] ?? scheduleRecord['schedule_lists'] ?? [];
            await prefs.setString('offline_cache_schedule_$groupName', json.encode(rawClassesList));
          }
        } catch (_) {}

        final String? cachedScheduleStr = prefs.getString(
          'offline_cache_schedule_$groupName',
        );

        if (cachedScheduleStr != null) {
          final List<dynamic> rawClassesList = json.decode(cachedScheduleStr);

          final currentDayString = DateFormat(
            'EEEE',
          ).format(DateTime.now()).toLowerCase();
          final now = DateTime.now();
          final currentMinutes = now.hour * 60 + now.minute;

          _todayClasses = rawClassesList
              .map((e) => Map<String, dynamic>.from(e))
              .where((c) {
                if ((c['day']?.toString().toLowerCase().trim() ?? '') !=
                    currentDayString) {
                  return false;
                }
                final timeRange = c['time']?.toString() ?? '';
                final parts = timeRange.split(' - ');
                if (parts.length == 2) {
                  final endMinutes = _parseTimeStr(parts[1]);
                  return currentMinutes <= endMinutes;
                }
                return true;
              })
              .toList();

          _todayClasses.sort(
            (a, b) => (a['time'] ?? '').toString().compareTo(
              (b['time'] ?? '').toString(),
            ),
          );
        } else {
          _todayClasses = [];
        }
      } else {
          _todayClasses = [];
      }

      final prefs = await SharedPreferences.getInstance();
      try {
        final calendarUrl = Uri.parse('${AuthService.apiBaseUrl}/api/schedule/fetch?department=Calendar&semester=Events');
        final calendarRes = await http.get(calendarUrl).timeout(const Duration(seconds: 12));
        if (calendarRes.statusCode == 200) {
          await prefs.setString('offline_cache_monthly_calendar', calendarRes.body);
        }
      } catch (_) {}

      final String? cachedEventsStr = prefs.getString(
        'offline_cache_monthly_calendar',
      );

      if (cachedEventsStr != null) {
        final List<dynamic> eventsData = json.decode(cachedEventsStr);
        final todayString =
            "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";

        _todayEvents = eventsData
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) {
              final eventDate =
                  e['Date']?.toString() ?? e['date']?.toString() ?? '';
              return eventDate == todayString;
            })
            .toList();
      }
    } catch (e) {
      debugPrint("⚠️ Dashboard Sync Error: $e");
      if (mounted) {
        setState(() => _hasSyncError = true);
        if (showError) {
          _showErrorSnackBar(
            'Connection failed. Please check your internet and try again.',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _loadAttendanceLogs(); // Force dynamic percentage refresh after sync completion
      }
    }
  }

  Future<void> _launchExternalUrl(String urlString) async {
    try {
      final Uri url = Uri.parse(urlString);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(
          'Unable to open the external website. Please try again.',
        );
      }
    }
  }

  // =========================================================================
  // TO-DO REMINDERS & NATIVE OS ALARM SYSTEM
  // =========================================================================

  Future<void> _initializeLocalNotif() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('launcher_icon');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotif.initialize(settings: initSettings);

    final androidPlatform = _localNotif
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlatform != null) {
      try {
        await androidPlatform.requestNotificationsPermission();
        await androidPlatform.requestExactAlarmsPermission();
      } catch (_) {}
    }
  }

  Future<void> _loadReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final String userRoll = AuthService.currentUser?.rollNumber ?? 'default';
      final str =
          prefs.getString('offline_tasks_$userRoll') ??
          prefs.getString('offline_custom_reminders');

      if (str != null) {
        final List<dynamic> decoded = json.decode(str);
        if (mounted) {
          setState(() {
            _reminders = decoded
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            _sortReminders();
          });
        }
      }

      await _syncScheduledNotifications();
    } catch (e) {
      debugPrint("Error loading reminders: $e");
    }
  }

  Future<void> _saveReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String userRoll = AuthService.currentUser?.rollNumber ?? 'default';

      await prefs.setString('offline_tasks_$userRoll', json.encode(_reminders));
      await _syncScheduledNotifications(); // Sync OS Alarms when saving
      await CloudSyncService.pushState(tasks: _reminders);
    } catch (e) {
      debugPrint("Error saving reminders: $e");
    }
  }

  Future<void> _syncScheduledNotifications() async {
    await _localNotif.cancelAll(); // Wipe all old pending alarms

    final now = DateTime.now();
    for (int i = 0; i < _reminders.length; i++) {
      final r = _reminders[i];
      if (r['is_completed'] == true) continue;

      final rTime = DateTime.tryParse(r['datetime'] ?? '');
      if (rTime != null && rTime.isAfter(now)) {
        final duration = rTime.difference(now);
        final scheduledTZDate = tz.TZDateTime.now(tz.local).add(duration);

        const notifDetails = NotificationDetails(
          android: AndroidNotificationDetails(
            'task_reminders_channel',
            'Task Reminders',
            channelDescription: 'Alerts for upcoming student tasks',
            importance: Importance.max,
            priority: Priority.high,
            icon: 'launcher_icon',
          ),
        );

        final int notifId = r['id'].hashCode.abs() % 100000;

        try {
          await _localNotif.zonedSchedule(
            id: notifId,
            title: r['title'] ?? 'Task Reminder',
            body: r['description'] ?? 'Scheduled task deadline reached.',
            scheduledDate: scheduledTZDate,
            notificationDetails: notifDetails,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
        } catch (e) {
          await _localNotif.zonedSchedule(
            id: notifId,
            title: r['title'] ?? 'Task Reminder',
            body: r['description'] ?? 'Scheduled task deadline reached.',
            scheduledDate: scheduledTZDate,
            notificationDetails: notifDetails,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      }
    }
  }

  void _sortReminders() {
    _reminders.sort((a, b) {
      if (a['is_completed'] != b['is_completed']) {
        return a['is_completed'] ? 1 : -1;
      }
      final dateA = DateTime.tryParse(a['datetime'] ?? '') ?? DateTime.now();
      final dateB = DateTime.tryParse(b['datetime'] ?? '') ?? DateTime.now();
      return dateA.compareTo(dateB);
    });
  }

  void _toggleReminderComplete(String id) {
    setState(() {
      final index = _reminders.indexWhere((r) => r['id'] == id);
      if (index != -1) {
              _reminders[index]['is_completed'] =
            !(_reminders[index]['is_completed'] ?? false);
        _sortReminders();
        _saveReminders();
      }
    });
  }

  void _deleteReminder(String id) {
    setState(() {
      _reminders.removeWhere((r) => r['id'] == id);
      _saveReminders();
    });
  }

  void _showAddEditReminderModal([Map<String, dynamic>? existingReminder]) {
    final theme = Theme.of(context);
    final systemExt = theme.extension<EduPortalThemeExtension>()!;

    final TextEditingController titleController = TextEditingController(
      text: existingReminder?['title'] ?? '',
    );
    final TextEditingController descController = TextEditingController(
      text: existingReminder?['description'] ?? '',
    );

    DateTime selectedDate =
        existingReminder != null && existingReminder['datetime'] != null
        ? DateTime.tryParse(existingReminder['datetime']) ?? DateTime.now()
        : DateTime.now();

    TimeOfDay selectedTime =
        existingReminder != null && existingReminder['datetime'] != null
        ? TimeOfDay.fromDateTime(
            DateTime.tryParse(existingReminder['datetime']) ?? DateTime.now(),
          )
        : TimeOfDay.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(EduDesignTokens.radius3xl),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: EduDesignTokens.slate300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      existingReminder == null
                          ? 'Create New Task'
                          : 'Edit Task',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 20),

                    TextField(
                      controller: titleController,
                      style: theme.textTheme.bodyLarge,
                      decoration: InputDecoration(
                        labelText: 'Task Title',
                        filled: true,
                        fillColor: systemExt.btnSoftBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            EduDesignTokens.radiusXl,
                          ),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: descController,
                      style: theme.textTheme.bodyLarge,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Description (Optional)',
                        filled: true,
                        fillColor: systemExt.btnSoftBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            EduDesignTokens.radiusXl,
                          ),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime.now().subtract(
                                  const Duration(days: 1),
                                ),
                                lastDate: DateTime(2030),
                              );
                              if (date != null)
                                setModalState(() => selectedDate = date);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: systemExt.btnSoftBg,
                                borderRadius: BorderRadius.circular(
                                  EduDesignTokens.radiusXl,
                                ),
                              ),
                              child: Row(
                                children: [
                                  SolarIcon(
                                    SolarIcons.Calendar,
                                    size: 18,
                                    color: theme.primaryColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    DateFormat(
                                      'MMM dd, yyyy',
                                    ).format(selectedDate),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: selectedTime,
                              );
                              if (time != null)
                                setModalState(() => selectedTime = time);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: systemExt.btnSoftBg,
                                borderRadius: BorderRadius.circular(
                                  EduDesignTokens.radiusXl,
                                ),
                              ),
                              child: Row(
                                children: [
                                  SolarIcon(
                                    SolarIcons.ClockCircle,
                                    size: 18,
                                    color: theme.primaryColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    selectedTime.format(context),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: () {
                        if (titleController.text.trim().isEmpty) return;

                        final finalDateTime = DateTime(
                          selectedDate.year,
                          selectedDate.month,
                          selectedDate.day,
                          selectedTime.hour,
                          selectedTime.minute,
                        );

                        setState(() {
                          if (existingReminder != null) {
                            final index = _reminders.indexWhere(
                              (r) => r['id'] == existingReminder['id'],
                            );
                            if (index != -1) {
                              _reminders[index] = {
                                'id': existingReminder['id'],
                                'title': titleController.text.trim(),
                                'description': descController.text.trim(),
                                'datetime': finalDateTime.toIso8601String(),
                                'is_completed':
                                    existingReminder['is_completed'],
                                'notified':
                                    finalDateTime.isBefore(DateTime.now())
                                    ? true
                                    : false,
                              };
                            }
                          } else {
                            _reminders.add({
                              'id': DateTime.now().millisecondsSinceEpoch
                                  .toString(),
                              'title': titleController.text.trim(),
                              'description': descController.text.trim(),
                              'datetime': finalDateTime.toIso8601String(),
                              'is_completed': false,
                              'notified': finalDateTime.isBefore(DateTime.now())
                                  ? true
                                  : false,
                            });
                          }
                          _sortReminders();
                          _saveReminders(); // Automatically triggers the native OS alarm sync
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            EduDesignTokens.radiusXl,
                          ),
                        ),
                      ),
                      child: Text(
                        existingReminder == null ? 'Save Task' : 'Update Task',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRemindersSection() {
    final theme = Theme.of(context);
    final systemExt = theme.extension<EduPortalThemeExtension>()!;

    if (_reminders.isEmpty) {
      return EduComponents.card(
        context: context,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          child: Center(
            child: Column(
              children: [
                const SolarIcon(
                  SolarIcons.ChecklistMinimalistic,
                  color: EduDesignTokens.slate300,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text('No Pending Tasks', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Add custom reminders or to-dos to keep track of your goals.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: _reminders.map((task) {
        final isCompleted = task['is_completed'] == true;
        final dateTime =
            DateTime.tryParse(task['datetime'] ?? '') ?? DateTime.now();
        final timeString = DateFormat('MMM dd, hh:mm a').format(dateTime);
        final isPastDue = dateTime.isBefore(DateTime.now()) && !isCompleted;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: EduComponents.card(
            context: context,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: InkWell(
                onTap: () => _toggleReminderComplete(task['id']),
                borderRadius: BorderRadius.circular(EduDesignTokens.radiusFull),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? EduDesignTokens.emerald500
                        : Colors.transparent,
                    border: Border.all(
                      color: isCompleted
                          ? EduDesignTokens.emerald500
                          : EduDesignTokens.slate300,
                      width: 2,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: isCompleted
                      ? const SolarIcon(
                          SolarIcons.CheckRead,
                          color: Colors.white,
                          size: 18,
                        )
                      : null,
                ),
              ),
              title: Text(
                task['title'] ?? 'Task',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                  color: isCompleted
                      ? EduDesignTokens.slate400
                      : theme.textTheme.bodyLarge?.color,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((task['description'] ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        task['description'],
                        style: TextStyle(
                          decoration: isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SolarIcon(
                        SolarIcons.ClockCircle,
                        size: 12,
                        color: isCompleted
                            ? EduDesignTokens.slate400
                            : (isPastDue
                                  ? EduDesignTokens.rose700
                                  : theme.primaryColor),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timeString,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isCompleted
                              ? EduDesignTokens.slate400
                              : (isPastDue
                                    ? EduDesignTokens.rose700
                                    : theme.primaryColor),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              trailing: PopupMenuButton<String>(
                icon: const SolarIcon(
                  SolarIcons.MenuDots,
                  color: EduDesignTokens.slate400,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                ),
                color: theme.cardColor,
                onSelected: (value) {
                  if (value == 'edit') {
                    _showAddEditReminderModal(task);
                  } else if (value == 'delete') {
                    _deleteReminder(task['id']);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        SolarIcon(
                          SolarIcons.PenN2,
                          size: 18,
                          color: theme.primaryColor,
                        ),
                        const SizedBox(width: 8),
                        const Text('Edit'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        SolarIcon(
                          SolarIcons.TrashBinMinimalistic,
                          size: 18,
                          color: systemExt.btnDangerText,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Delete',
                          style: TextStyle(color: systemExt.btnDangerText),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // =========================================================================
  // SECURE DIGITAL ID & MOBILE SCANNER
  // =========================================================================
  void _showDigitalIdModal() {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) {
        bool isScanning = false;
        bool isProcessingScan = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(16),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(
                    EduDesignTokens.radius3xl,
                  ),
                  border: Border.all(color: systemExt.borderNeutral),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Digital Identity',
                            style: theme.textTheme.titleMedium,
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const SolarIcon(
                              SolarIcons.CloseCircle,
                              color: EduDesignTokens.slate400,
                            ),
                          ),
                        ],
                      ),
                    ),

                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: isScanning
                          ? _buildScannerView(
                              theme,
                              systemExt,
                              isProcessingScan,
                              (capture) async {
                                if (isProcessingScan) return;
                                final List<Barcode> barcodes = capture.barcodes;
                                if (barcodes.isNotEmpty &&
                                    barcodes.first.rawValue != null) {
                                  setModalState(() => isProcessingScan = true);

                                  final decryptedMap =
                                      CryptoService.decryptPayload(
                                        barcodes.first.rawValue!,
                                      );

                                  Navigator.pop(context); // Close scanner modal
                                  if (decryptedMap != null) {
                                    _showScannedStudentDetails(decryptedMap);
                                  } else {
                                    _showErrorSnackBar(
                                      'Invalid or Foreign QR Code Detected!',
                                    );
                                  }
                                }
                              },
                            )
                          : Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: StudentIdCard(),
                            ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: EduComponents.primaryGradientButton(
                        context: context,
                        onPressed: () =>
                            setModalState(() => isScanning = !isScanning),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isScanning
                                  ? Icons.person_rounded
                                  : Icons.qr_code_scanner,
                              size: 20,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isScanning ? 'Show My ID' : 'Scan Authenticity',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildScannerView(
    ThemeData theme,
    EduPortalThemeExtension systemExt,
    bool isProcessing,
    Function(BarcodeCapture) onDetect,
  ) {
    return Container(
      key: const ValueKey('scanner'),
      height: 300,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
        child: Stack(
          alignment: Alignment.center,
          children: [
            MobileScanner(
              controller: MobileScannerController(
                detectionSpeed: DetectionSpeed.noDuplicates,
              ),
              onDetect: onDetect,
            ),
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            if (isProcessing)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.greenAccent),
                ),
              ),
            Positioned(
              bottom: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Align QR code within frame',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showScannedStudentDetails(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
          ),
          title: Row(
            children: [
              const SolarIcon(
                SolarIcons.VerifiedCheck,
                color: Colors.greenAccent,
              ),
              const SizedBox(width: 8),
              Text('Authentic Identity', style: theme.textTheme.titleMedium),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Name: ${data['name']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Roll No: ${data['roll']}'),
              const SizedBox(height: 8),
              Text('Course: ${data['dept']}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // =========================================================================
  // ASYNC MODALS FOR DIRECTORY AND LIBRARY
  // =========================================================================
  Future<Map<String, List<Map<String, dynamic>>>>
  _fetchStaffFromBackend() async {
    try {
      final token = await AuthService.getAuthToken() ?? '';
      final url = Uri.parse(
        '${AuthService.apiBaseUrl}/api/directory/staff?token=$token',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final List<dynamic> raw = json.decode(response.body);
        final Map<String, List<Map<String, dynamic>>> grouped = {};
        for (var item in raw) {
          final dept = item['department'] ?? 'Other';
          grouped
              .putIfAbsent(dept, () => [])
              .add(Map<String, dynamic>.from(item));
        }
        return grouped;
      }
      throw Exception('Server rejected payload');
    } catch (e) {
      debugPrint('Staff Directory Sync Error: $e');
      throw Exception('Connection timeout or network error');
    }
  }

  void _showStaffDirectoryModal() {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(EduDesignTokens.radius3xl),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: EduDesignTokens.slate300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? EduDesignTokens.sky500.withOpacity(0.15)
                          : EduDesignTokens.sky500.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: SolarIcon(
                      SolarIcons.UsersGroupRounded,
                      color: EduDesignTokens.sky500,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text('Staff Directory', style: theme.textTheme.titleLarge),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
                future: _fetchStaffFromBackend(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: theme.primaryColor,
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text(
                          "Unable to connect to the directory. Please check your internet connection.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: EduDesignTokens.rose700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }

                  final directory = snapshot.data ?? {};
                  if (directory.isEmpty) {
                    return const Center(
                      child: Text("No staff members registered."),
                    );
                  }

                  return DefaultTabController(
                    length: directory.keys.length,
                    child: Column(
                      children: [
                        TabBar(
                          isScrollable: true,
                          indicatorColor: theme.primaryColor,
                          labelColor: theme.primaryColor,
                          unselectedLabelColor: EduDesignTokens.slate400,
                          tabs: directory.keys
                              .map((k) => Tab(text: k))
                              .toList(),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: directory.keys.map((category) {
                              final staff = directory[category]!;
                              return ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: staff.length,
                                itemBuilder: (context, index) {
                                  final person = staff[index];
                                  return Card(
                                    elevation: 0,
                                    margin: const EdgeInsets.only(bottom: 12),
                                    shape: RoundedRectangleBorder(
                                      side: BorderSide(
                                        color: systemExt.borderNeutral,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        EduDesignTokens.radiusXl,
                                      ),
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.all(16),
                                      leading: CircleAvatar(
                                        backgroundColor:
                                            EduDesignTokens.slate100,
                                        child: Text(
                                          person['name'][0],
                                          style: const TextStyle(
                                            color: EduDesignTokens.slate800,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        person['name'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text(
                                            person['role'],
                                            style: TextStyle(
                                              color: theme.primaryColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            person['email'],
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      trailing: IconButton(
                                        icon: const SolarIcon(
                                          SolarIcons.Copy,
                                          size: 20,
                                          color: EduDesignTokens.slate400,
                                        ),
                                        onPressed: () {
                                          Clipboard.setData(
                                            ClipboardData(
                                              text: person['email'],
                                            ),
                                          );
                                          ScaffoldMessenger.of(
                                            context,
                                          ).hideCurrentSnackBar();
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('Email copied!'),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  );
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchLibraryFromBackend() async {
    try {
      final token = await AuthService.getAuthToken() ?? '';
      final url = Uri.parse(
        '${AuthService.apiBaseUrl}/api/library/books?token=$token',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      }
      throw Exception('Server rejected payload');
    } catch (e) {
      debugPrint('Resources Sync Error: $e');
      throw Exception('Connection timeout or network error');
    }
  }

  void _showLibraryModal() {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(EduDesignTokens.radius3xl),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: EduDesignTokens.slate300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? EduDesignTokens.emerald500.withOpacity(0.15)
                          : EduDesignTokens.emerald500.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      color: EduDesignTokens.emerald600,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text('E-Resource Portal', style: theme.textTheme.titleLarge),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _fetchLibraryFromBackend(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: theme.primaryColor,
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text(
                          "Unable to connect to the Resources. Please check your internet connection.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: EduDesignTokens.rose700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }

                  final books = snapshot.data ?? [];
                  if (books.isEmpty) {
                    return const Center(
                      child: Text("Resources is currently empty."),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: systemExt.borderNeutral),
                          borderRadius: BorderRadius.circular(
                            EduDesignTokens.radiusXl,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          title: Text(
                            book['title'] ?? 'Unknown Title',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Row(
                              children: [
                                const SolarIcon(
                                  SolarIcons.User,
                                  size: 14,
                                  color: EduDesignTokens.slate400,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    book['author'] ?? 'Unknown',
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: ElevatedButton.icon(
                            onPressed: () =>
                                _launchExternalUrl(book['url'] ?? ''),
                            icon: const Icon(
                              Icons.arrow_outward_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Read',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: EduDesignTokens.emerald600,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  EduDesignTokens.radiusM,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // WIDGET LAYOUTS
  // =========================================================================
  Widget _buildAcademicIdentityCard() {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final user = AuthService.currentUser;

    final name = user?.name ?? 'Student';
    final firstName = name.split(' ').first;
    final roll = user?.rollNumber ?? 'Not Assigned';
    final branch = user?.department ?? 'B.Tech';
    final semester = user?.semester ?? '4';
    
    final dobString = user?.dob ?? '2000-01-01'; 

    final now = DateTime.now();
    final currentMonth = now.month.toString().padLeft(2, '0');
    final currentDay = now.day.toString().padLeft(2, '0');
    
    final isBirthday = dobString.length >= 10 && dobString.substring(5) == "$currentMonth-$currentDay";

    // Progressive Hierarchy:
    // 1. Downloaded Custom Background via Silent Push Notifications (if available and not expired)
    // 2. Local Custom Birthday Card Background (if active)
    // 3. System Theme Gradient Color
    DecorationImage? decorationImage;
    bool hasCustomBg = _customBgImagePath != null && File(_customBgImagePath!).existsSync();

    if (hasCustomBg) {
      decorationImage = DecorationImage(
        image: FileImage(File(_customBgImagePath!)),
        fit: BoxFit.cover,
      );
    } else if (isBirthday) {
      decorationImage = const DecorationImage(
        image: AssetImage('assets/images/birthday_bg.png'),
        fit: BoxFit.cover,
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: (hasCustomBg || isBirthday) ? null : systemExt.primaryGradient,
        image: decorationImage,
        borderRadius: BorderRadius.circular(EduDesignTokens.radius3xl),
        boxShadow: systemExt.authCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isBirthday ? 'Happy B\'day dear, ' : '$_greeting',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      firstName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(EduDesignTokens.radiusFull),
                        border: Border.all(color: Colors.white.withOpacity(0.22)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                            size: 14,
                            color: _isOnline ? Colors.greenAccent : EduDesignTokens.rose100,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isOnline ? 'Online' : 'Offline',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              Row(
                children: [
                  _buildAttendanceRingGauge(),
                  const SizedBox(width: 12),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                      border: Border.all(color: Colors.white.withOpacity(0.4)),
                    ),
                    child: Center(
                      child: SolarIcon(
                        isBirthday ? SolarIcons.Gift : SolarIcons.User,
                        weight: SolarIconWeight.bold,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.15),
              borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildIdentityMetric('ROLL NO', roll),
                Container(
                  width: 1,
                  height: 30,
                  color: Colors.white.withOpacity(0.2),
                ),
                _buildIdentityMetric('COURSE', branch),
                Container(
                  width: 1,
                  height: 30,
                  color: Colors.white.withOpacity(0.2),
                ),
                _buildIdentityMetric('SEMESTER', semester),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceRingGauge() {
    final bool isLowAttendance = _attendancePercentage < 75.0;
    final color = isLowAttendance ? EduDesignTokens.rose100 : Colors.white;
    final trackColor = Colors.white.withOpacity(0.15);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              value: _attendancePercentage / 100.0,
              strokeWidth: 3.5,
              backgroundColor: trackColor,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "${_attendancePercentage.toStringAsFixed(1)}%",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                isLowAttendance ? "Low Attendance" : "On Track",
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionsBar() {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget actionTile(
      dynamic iconData,
      String label,
      Color color,
      VoidCallback onTap,
    ) {
      return Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isDark ? color.withOpacity(0.15) : color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
              border: Border.all(
                color: isDark ? color.withOpacity(0.3) : Colors.transparent,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
                child: Center(
                  child: EduComponents.icon(
                    context: context,
                    iconData: iconData,
                    color: color,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: systemExt.btnSoftText,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        actionTile(
          Icons.qr_code_scanner,
          'Student ID',
          EduDesignTokens.indigo500,
          _showDigitalIdModal,
        ),
        actionTile(
          Icons.menu_book_rounded,
          'Resources',
          EduDesignTokens.emerald500,
          _showLibraryModal,
        ),
        actionTile(
          Icons.groups_rounded,
          'Staff',
          EduDesignTokens.sky500,
          _showStaffDirectoryModal,
        ),
        actionTile(
          Icons.public,
          'Website',
          EduDesignTokens.purple600,
          () =>
              _launchExternalUrl('https://erp.ddugu.ac.in/student_login.aspx'),
        ),
      ],
    );
  }

  Widget _buildCampusWifiCard() {
    final theme = Theme.of(context);
    final user = AuthService.currentUser;

    final username = "ddu-globus";
    final password = user != null ? "Ddu@2023" : "Not Available";

    Widget wifiRow(String label, String value) {
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelSmall),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const SolarIcon(
              SolarIcons.Copy,
              size: 20,
              color: EduDesignTokens.slate400,
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (mounted) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    duration: const Duration(milliseconds: 1500),
                    content: Row(
                      children: [
                        EduComponents.icon(
                          context: context,
                          iconData: EduIcons.success,
                          color: Colors.greenAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '$label copied successfully!',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: theme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        EduDesignTokens.radiusXl,
                      ),
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ],
      );
    }

    return EduComponents.card(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: EduDesignTokens.sky500.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const SolarIcon(
                    SolarIcons.WiFiRouterMinimalistic,
                    color: EduDesignTokens.sky500,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Campus Wi-Fi', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        'Secure Student Gateway',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            wifiRow('SSID / Network Name', 'DDUGU-GKP'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4.0),
              child: Divider(height: 1, thickness: 1),
            ),
            wifiRow('Username', username),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4.0),
              child: Divider(height: 1, thickness: 1),
            ),
            wifiRow('Password', password),
          ],
        ),
      ),
    );
  }

  // To-Do Reminders State: Independent Dedicated Tile For Events
  Widget _buildTodayEventTile() {
    if (_todayEvents.isEmpty) return const SizedBox.shrink(); // Hide entirely if no events

    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Today's Events",
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ..._todayEvents.map((event) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: EduComponents.card(
              context: context,
              child: Container(
                decoration: BoxDecoration(
                  color: systemExt.btnDangerBg,
                  borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
                  border: Border.all(color: systemExt.btnDangerBorder, width: 1.5),
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: EduDesignTokens.rose100.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      child: EduComponents.icon(
                        context: context,
                        iconData: Icons.star_rounded,
                        color: systemExt.btnDangerText,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (event['Type'] ?? 'Event').toString().toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: systemExt.btnDangerText,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            event['Title'] ?? 'Special Event',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: systemExt.btnDangerText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
        const SizedBox(height: 32),
      ],
    );
  }

  /// Custom decorator that formats the title based on the active tracking state on home screen.
  Widget _buildSubjectHeader(String subject, String status, TextStyle? baseStyle) {
    TextDecoration? decoration;
    Color? textColor = baseStyle?.color;
    Widget? iconMark;

    if (status == 'cancelled') {
      decoration = TextDecoration.lineThrough;
      textColor = EduDesignTokens.slate400;
      iconMark = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: EduDesignTokens.slate100.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'CANCELLED',
          style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: EduDesignTokens.slate400),
        ),
      );
    } else if (status == 'attended') {
      iconMark = const Icon(Icons.check_circle_rounded, size: 16, color: EduDesignTokens.emerald500);
    } else if (status == 'missed') {
      iconMark = const Icon(Icons.cancel_rounded, size: 16, color: EduDesignTokens.rose700);
    } else if (status == 'holiday') {
      textColor = const Color(0xFF0284C7); // Safe equivalent for sky600
      iconMark = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F9FF), // Safe equivalent for sky50
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'HOLIDAY',
          style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            subject,
            style: baseStyle?.copyWith(
              decoration: decoration,
              color: textColor,
              fontStyle: status == 'holiday' ? FontStyle.italic : FontStyle.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (iconMark != null) ...[
          const SizedBox(width: 8),
          iconMark,
        ],
      ],
    );
  }

  /// Symmetrical quick-logger built for inline interaction on the home tab.
  Widget _buildAttendanceActionBar(Map<String, dynamic> classData, String currentStatus) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final rawTime = classData['time'] ?? '10:00 - 11:00';
    final subject = classData['subject'] ?? 'Unspecified Subject';
    final dateKey = _formatDateToKey(DateTime.now());

    Widget buildStatusItem({
      required String status,
      required IconData icon,
      required String label,
      required Color activeColor,
      required Color activeBg,
    }) {
      final bool isSelected = currentStatus == status;
      return Expanded(
        child: GestureDetector(
          onTap: () async {
            final targetStatus = isSelected ? 'none' : status;
            await AttendanceDbService.logAttendance(
              date: dateKey,
              timeSlot: rawTime.toString(),
              subject: subject,
              status: targetStatus,
            );
            await CloudSyncService.pushState(tasks: _reminders);
            await _loadAttendanceLogs(); // Sync state on database write
            // scheduleRefreshNotifier is ValueNotifier<int>, increment to trigger redraws safely
            AppStateNotifier.scheduleRefreshNotifier.value = AppStateNotifier.scheduleRefreshNotifier.value + 1;
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(EduDesignTokens.radiusM),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? activeColor : EduDesignTokens.slate500,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? activeColor : EduDesignTokens.slate500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: systemExt.btnSoftBg.withOpacity(0.5),
        borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
        border: Border.all(color: systemExt.borderNeutral.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          buildStatusItem(
            status: 'attended',
            icon: Icons.check_circle_rounded,
            label: 'Attended',
            activeColor: EduDesignTokens.emerald600,
            activeBg: EduDesignTokens.emerald50.withOpacity(0.15),
          ),
          buildStatusItem(
            status: 'missed',
            icon: Icons.cancel_rounded,
            label: 'Missed',
            activeColor: EduDesignTokens.rose700,
            activeBg: EduDesignTokens.rose50.withOpacity(0.15),
          ),
          buildStatusItem(
            status: 'cancelled',
            icon: Icons.block_flipped,
            label: 'Cancelled',
            activeColor: const Color(0xFFD97706), // Safe equivalent for amber600
            activeBg: const Color(0xFFFEF3C7).withOpacity(0.15), // Safe equivalent for amber50
          ),
          buildStatusItem(
            status: 'holiday',
            icon: Icons.beach_access_rounded,
            label: 'Holiday',
            activeColor: const Color(0xFF0284C7), // Safe equivalent for sky600
            activeBg: const Color(0xFFF0F9FF).withOpacity(0.15), // Safe equivalent for sky50
          ),
          buildStatusItem(
            status: 'none',
            icon: Icons.refresh_rounded,
            label: 'Reset',
            activeColor: const Color(0xFF475569), // Safe equivalent for slate600
            activeBg: EduDesignTokens.slate100.withOpacity(0.15),
          ),
        ],
      ),
    );
  }

  Widget _buildTodaySchedule() {
    final theme = Theme.of(context);
    final systemExt = theme.extension<EduPortalThemeExtension>()!;

    if (_todayClasses.isEmpty) {
      return EduComponents.card(
        context: context,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          child: Center(
            child: Column(
              children: [
                const SolarIcon(
                  SolarIcons.Calendar,
                  color: EduDesignTokens.slate300,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text('Schedule Cleared!', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  _hasSyncError
                      ? 'Unable to sync schedule due to a network error. Pull down to refresh.'
                      : 'All classes for today are completed or none were scheduled.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final List<Widget> scheduleWidgets = [];

    // Render Remaining / Active Classes Only (Events are rendered separately now)
    for (var classData in _todayClasses) {
      final rawTime = classData['time'] ?? '10:00 - 11:00';
      final subject = classData['subject'] ?? 'Unspecified Subject';
      final room = classData['room'] ?? 'TBA';

      bool isOngoing = false;
      final now = DateTime.now();
      final currentMinutes = now.hour * 60 + now.minute;
      final parts = rawTime.split(' - ');
      if (parts.length == 2) {
        final startMinutes = _parseTimeStr(parts[0]);
        final endMinutes = _parseTimeStr(parts[1]);
        isOngoing =
            currentMinutes >= startMinutes && currentMinutes <= endMinutes;
      }

      // Read status from today's memory logger map
      final String currentStatus = _todayAttendanceLog["${rawTime}|${subject}"] ?? 'none';

      Color? borderColor;
      Color? cardBgColor = Colors.transparent;
      double borderWidth = 1.5;

      if (isOngoing) {
        borderColor = systemExt.borderFocus;
        borderWidth = 2.0;
        cardBgColor = EduDesignTokens.indigo50.withOpacity(0.15);
      } else if (currentStatus == 'attended') {
        borderColor = EduDesignTokens.emerald500.withOpacity(0.4);
      } else if (currentStatus == 'missed') {
        borderColor = EduDesignTokens.rose700.withOpacity(0.4);
      } else if (currentStatus == 'cancelled') {
        borderColor = EduDesignTokens.slate300.withOpacity(0.4);
        cardBgColor = theme.cardColor.withOpacity(0.6);
      } else if (currentStatus == 'holiday') {
        borderColor = EduDesignTokens.sky500.withOpacity(0.4);
      }

      scheduleWidgets.add(
        Container(
          key: ValueKey("${_formatDateToKey(DateTime.now())}_${rawTime}_$subject"),
          margin: const EdgeInsets.only(bottom: 12),
          child: EduComponents.card(
            context: context,
            child: Container(
              decoration: BoxDecoration(
                color: cardBgColor,
                borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
                border: borderColor != null
                    ? Border.all(color: borderColor, width: borderWidth)
                    : null,
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isOngoing
                              ? EduDesignTokens.indigo50.withOpacity(0.8)
                              : systemExt.btnSoftBg,
                          borderRadius: BorderRadius.circular(
                            EduDesignTokens.radiusXl,
                          ),
                          border: Border.all(
                            color: isOngoing
                                ? EduDesignTokens.indigo500.withOpacity(0.2)
                                : systemExt.btnSoftBorder,
                          ),
                        ),
                        child: Text(
                          rawTime.toString().replaceAll(' - ', '\n'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isOngoing
                                ? EduDesignTokens.indigo700
                                : systemExt.btnSoftText,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSubjectHeader(
                              subject,
                              currentStatus,
                              theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const SolarIcon(
                                  SolarIcons.MapPoint,
                                  size: 14,
                                  color: EduDesignTokens.slate400,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "Room $room",
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 12,
                                  ),
                                ),
                                if (isOngoing) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: EduDesignTokens.emerald500.withOpacity(
                                        0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      "ONGOING",
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: EduDesignTokens.emerald700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  _buildAttendanceActionBar(classData, currentStatus),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(children: scheduleWidgets);
  }

  Widget _buildRecentVaultItems() {
    final theme = Theme.of(context);
    final systemExt = theme.extension<EduPortalThemeExtension>()!;

    if (_recentVaultItems.isEmpty) {
      return EduComponents.card(
        context: context,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          child: Center(
            child: Column(
              children: [
                const SolarIcon(
                  SolarIcons.Folder,
                  color: EduDesignTokens.slate300,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text('Vault is Empty', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  _hasSyncError
                      ? 'Unable to sync vault due to a network error. Pull down to refresh.'
                      : 'Your recently synced documents will appear here.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: _recentVaultItems.map((item) {
        final filename = item['file_name']?.toString() ?? 'Unnamed File';
        final extension = item['extension']?.toString().toUpperCase() ?? 'FILE';
        final sizeBytes = item['file_size'] as int? ?? 0;
        final sizeKb = (sizeBytes / 1024).toStringAsFixed(1);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: EduComponents.card(
            context: context,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: systemExt.btnSoftBg,
                  borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                ),
                child: EduComponents.icon(
                  context: context,
                  iconData: const SolarIcon(
                    SolarIcons.DocumentInNotes,
                    weight: SolarIconWeight.outline,
                  ),
                  color: systemExt.btnSoftText,
                  size: 24,
                ),
              ),
              title: Text(
                filename,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '$extension • $sizeKb KB',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11),
              ),
              trailing: EduComponents.icon(
                context: context,
                iconData: const SolarIcon(
                  SolarIcons.AltArrowRight,
                  weight: SolarIconWeight.outline,
                ),
                color: EduDesignTokens.slate400,
                size: 18,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // =========================================================================
  // MAIN WRAPPER COMPOSITION (Dashboard Tab + Bottom Nav Integration)
  // =========================================================================

  Widget _buildDashboardTab() {
    final textTheme = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () async {
        await _refreshEverything();
      },
      color: Theme.of(context).primaryColor,
      backgroundColor: Theme.of(context).cardColor,
      child: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).primaryColor,
              ),
            )
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Identity Context
                  _buildAcademicIdentityCard(),
                  const SizedBox(height: 32),

                  // 2. Fast Operations Grid
                  _buildQuickActionsBar(),
                  const SizedBox(height: 32),

                  // 3. Isolated Event & Schedule Render Pipeline
                  _buildTodayEventTile(), // Will automatically vanish if no events are active
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Today's Schedule",
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        DateFormat('MMM dd').format(DateTime.now()),
                        style: textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTodaySchedule(),
                  const SizedBox(height: 32),

                  // 4. Utility Integrations (WiFi)
                  Text(
                    "Campus Services",
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildCampusWifiCard(),
                  const SizedBox(height: 32),

                  // 5. To-Do Tasks & Reminders Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Tasks & Reminders",
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () => _showAddEditReminderModal(),
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).primaryColor.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: SolarIcon(
                            SolarIcons.AddCircle,
                            color: Theme.of(context).primaryColor,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildRemindersSection(),
                  const SizedBox(height: 32),

                  // 6. Cloud Storage Synchronization Stream
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Recent Uploads",
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).primaryColor.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: SolarIcon(
                          SolarIcons.FolderWithFiles,
                          color: Theme.of(context).primaryColor,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildRecentVaultItems(),
                  const SizedBox(height: 48), // Bottom padding scroll allowance
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final String currentUserId = AuthService.currentUser?.rollNumber ?? '';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: systemExt.pageBackground),
        child: SafeArea(
          child: IndexedStack(
            index: _currentIndex,
            children: [
              _buildDashboardTab(), // Tab 0: Home / Dashboard
              ChatGroupPage(currentUserId: currentUserId), // Tab 1: Chat Room
              const CalendarScreen(), // Tab 2: Schedules & Events
              VaultPage(currentUserId: currentUserId), // Tab 3: Encrypted Vault
              const ProfileScreen(), // Tab 4: Student Profile Settings
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: Theme.of(context).cardColor,
        elevation: 0,
        indicatorColor: Theme.of(context).brightness == Brightness.dark
            ? EduDesignTokens.indigo500.withOpacity(0.2)
            : EduDesignTokens.indigo50,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: const [
          NavigationDestination(
            icon: SolarIcon(SolarIcons.HomeN2, weight: SolarIconWeight.outline),
            selectedIcon: SolarIcon(
              SolarIcons.HomeN2,
              weight: SolarIconWeight.bold,
            ),
            label: 'Home',
          ),
          NavigationDestination(
            icon: SolarIcon(
              SolarIcons.ChatRoundDots,
              weight: SolarIconWeight.outline,
            ),
            selectedIcon: SolarIcon(
              SolarIcons.ChatRoundDots,
              weight: SolarIconWeight.bold,
            ),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: SolarIcon(
              SolarIcons.Calendar,
              weight: SolarIconWeight.outline,
            ),
            selectedIcon: SolarIcon(
              SolarIcons.Calendar,
              weight: SolarIconWeight.bold,
            ),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: SolarIcon(SolarIcons.Folder, weight: SolarIconWeight.outline),
            selectedIcon: SolarIcon(
              SolarIcons.Folder,
              weight: SolarIconWeight.bold,
            ),
            label: 'Files',
          ),
          NavigationDestination(
            icon: SolarIcon(SolarIcons.User, weight: SolarIconWeight.outline),
            selectedIcon: SolarIcon(
              SolarIcons.User,
              weight: SolarIconWeight.bold,
            ),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
