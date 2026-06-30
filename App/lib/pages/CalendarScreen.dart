// ignore_for_file: file_names

import 'dart:convert';
import 'dart:async'; // 💡 Added for TimeoutException handling
import 'dart:io'; // 💡 Added for SocketException handling
import 'package:edu_portal/constants/design_system.dart';
import 'package:flutter/foundation.dart'; 
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/attendance_db_service.dart';
import '../services/cloud_sync_service.dart';
import '../constants/theme.dart';

// 💡 High Performance Top-Level Isolation Parsers.
// These run entirely on background threads away from the main UI pipeline to prevent skipping frames.
List<Map<String, dynamic>> _isolateJsonDecodeList(String body) {
  final List<dynamic> decoded = jsonDecode(body);
  return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final PageController _pageController;
  int _activeDayIndex = 0;
  bool _isLoading = false;
  String? _errorMessage;
  String? _currentSubscription;

  late DateTime _currentMonthDate;
  bool _wasPageVisible = false;

  final List<String> _dayShortNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  final List<String> _dbDayKeys = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];

  final Map<String, List<Map<String, dynamic>>> _dailyClasses = {
    'monday': [], 'tuesday': [], 'wednesday': [], 'thursday': [], 'friday': [], 'saturday': [],
  };

  final Map<String, List<Map<String, dynamic>>> _monthlyEvents = {};

  // 💡 Memory map tracking for the selected active week -> (date -> (time|subject -> status))
  Map<String, Map<String, String>> _weeklyAttendanceLog = {};

  @override
  void initState() {
    super.initState();
    _currentMonthDate = DateTime.now();

    final weekdayIndex = DateTime.now().weekday;
    if (weekdayIndex >= 1 && weekdayIndex <= 6) {
      _activeDayIndex = weekdayIndex - 1;
    } else {
      _activeDayIndex = 0; // default to Monday if today is Sunday
    }
    _pageController = PageController(initialPage: _activeDayIndex);

    _loadInitialSubscriptionAndData();
    
    // 💡 Listen for schedule changes from ProfileScreen to instantly redraw 
    AppStateNotifier.scheduleRefreshNotifier.addListener(_onGlobalScheduleUpdate);
  }

  Future<void> _onGlobalScheduleUpdate() async {
    if (mounted) {
      final sub = await AuthService.getSubscribedSchedule();
      final latestSub = (sub != null && sub.isNotEmpty) ? sub : null;
      
      if (latestSub != _currentSubscription) {
        // Section subscription changed, refresh entire schedule view
        setState(() {
          _currentSubscription = latestSub;
        });
        await _loadAttendanceLogs();
        _initializeScheduleAndCalendar(latestSub, forceSync: true);
      } else {
        // silenty refresh local logs without modifying page layout index
        await _loadAttendanceLogs();
      }
    }
  }

  @override
  void dispose() {
    AppStateNotifier.scheduleRefreshNotifier.removeListener(_onGlobalScheduleUpdate);
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialSubscriptionAndData() async {
    final sub = await AuthService.getSubscribedSchedule();
    // 💡 Strictly convert empty strings to null to ensure proper state resets
    final validSub = (sub != null && sub.isNotEmpty) ? sub : null;
    
    if (mounted) {
      setState(() {
        _currentSubscription = validSub;
      });
    }
    await _loadAttendanceLogs(); // Load DB tracker state before compiling UI list
    _initializeScheduleAndCalendar(validSub);
  }

  /// Safely resolves the exact Gregorian date for each relative day index of the active school week.
  DateTime _getDateOfThisWeek(int weekdayIndex) {
    final now = DateTime.now();
    // Find Monday of the current week (weekday range: 1 - 7)
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return monday.add(Duration(days: weekdayIndex));
  }

  Future<void> _loadAttendanceLogs() async {
    final List<String> weekDates = List.generate(6, (idx) => _formatDateToKey(_getDateOfThisWeek(idx)));
    final logs = await AttendanceDbService.getWeeklyAttendance(weekDates);
    if (mounted) {
      setState(() {
        _weeklyAttendanceLog = logs;
      });
    }
  }

  String _formatDateToKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  void _resetToToday() {
    final now = DateTime.now();
    final weekdayIndex = now.weekday;
    int targetPage = 0;
    if (weekdayIndex >= 1 && weekdayIndex <= 6) {
      targetPage = weekdayIndex - 1;
    }

    setState(() {
      _currentMonthDate = now;
      _activeDayIndex = targetPage;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(targetPage);
      }
    });
  }

  Future<void> _checkAndResetFocus({bool forceSync = false}) async {
    final sub = await AuthService.getSubscribedSchedule();
    final latestSub = (sub != null && sub.isNotEmpty) ? sub : null;
    
    if (latestSub != _currentSubscription) {
      if (mounted) {
        setState(() {
          _currentSubscription = latestSub;
        });
      }
    }
    
    await _loadAttendanceLogs(); // Sync local states
    _initializeScheduleAndCalendar(latestSub, forceSync: forceSync);
  }

  // Cache Utilities optimized to run sequentially
  Future<void> _saveMonthlyCalendarToCache(List<Map<String, dynamic>> eventsList) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('offline_cache_monthly_calendar', json.encode(eventsList));
  }

  Future<List<Map<String, dynamic>>?> _loadMonthlyCalendarFromCache() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('offline_cache_monthly_calendar');
    if (jsonStr == null) return null;
    return compute(_isolateJsonDecodeList, jsonStr); 
  }

  Future<void> _saveScheduleToCache(String groupName, List<Map<String, dynamic>> classesList) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('offline_cache_schedule_$groupName', json.encode(classesList));
  }

  Future<List<Map<String, dynamic>>?> _loadScheduleFromCache(String groupName) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('offline_cache_schedule_$groupName');
    if (jsonStr == null) return null;
    return compute(_isolateJsonDecodeList, jsonStr); 
  }

  Future<void> _initializeScheduleAndCalendar(String? groupName, {bool forceSync = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // 💡 Instantly wipe any lingering classes from memory to guarantee ghost caches never display
    _distributeClasses([]);

    List<Map<String, dynamic>>? cachedClasses;
    if (groupName != null) {
      cachedClasses = await _loadScheduleFromCache(groupName);
    }
    
    final cachedCalendar = await _loadMonthlyCalendarFromCache();

    if (cachedClasses != null) _distributeClasses(cachedClasses);
    if (cachedCalendar != null) _indexMonthlyEvents(cachedCalendar);

    // Stop loading early if we have the caches we require AND we aren't forcing a sync
    final bool hasNeededCache = (groupName == null || cachedClasses != null) && (cachedCalendar != null);
    
    if (hasNeededCache && !forceSync) {
      if (mounted) setState(() { _isLoading = false; });
      _syncAllLiveRecords(groupName, isSilentBackgroundSync: true);
    } else {
      await _syncAllLiveRecords(groupName, isSilentBackgroundSync: false);
    }
  }

  void _indexMonthlyEvents(List<Map<String, dynamic>> rawEventsList) {
    setState(() {
      _monthlyEvents.clear();
      for (var item in rawEventsList) {
        final rawDate = item['Date']?.toString() ?? item['date']?.toString() ?? '';
        if (rawDate.isNotEmpty) {
          _monthlyEvents.putIfAbsent(rawDate, () => []).add(item);
        }
      }
    });
  }

  void _distributeClasses(List<Map<String, dynamic>> rawClassesList) {
    setState(() {
      for (var key in _dailyClasses.keys) {
        _dailyClasses[key] = [];
      }
      for (var item in rawClassesList) {
        final String day = (item['day'] ?? '').toString().toLowerCase().trim();
        if (_dailyClasses.containsKey(day)) {
          _dailyClasses[day]!.add(item);
        }
      }
      for (var dayKey in _dailyClasses.keys) {
        _dailyClasses[dayKey]!.sort((a, b) => (a['time'] ?? '').toString().compareTo((b['time'] ?? '').toString()));
      }
      // 💡 UX PATCH: Removed the _activeDayIndex overwrite and jumpToPage triggers here.
      // This completely stops the day selector from resetting focus during background changes.
    });
  }

  Future<void> _syncAllLiveRecords(
    String? groupName, {
    bool isSilentBackgroundSync = false,
    bool isManualRefresh = false,
  }) async {
    if (!isSilentBackgroundSync && !isManualRefresh) {
      setState(() { _isLoading = true; });
    }

    bool weeklySuccess = false;
    bool calendarSuccess = false;

    final user = AuthService.currentUser;
    final String dept = user?.department ?? '';
    final String semester = user?.semester ?? '4';
    final String? token = await AuthService.getAuthToken();

    // 💡 Task 1: Sync Weekly Classes ONLY if the user is actively subscribed
    if (groupName != null && groupName.isNotEmpty) {
      try {
        final url = Uri.parse(
          '${AuthService.apiBaseUrl}/api/schedule/fetch'
          '?department=${Uri.encodeComponent(dept)}'
          '&semester=${Uri.encodeComponent(semester)}'
          '&group_name=${Uri.encodeComponent(groupName)}'
          '&date=${Uri.encodeComponent(_formatDateToKey(DateTime.now()))}'
        );

        // 💡 SECURE BACKEND CALL WITH TIMEOUT
        final response = await http.get(url, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        }).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final List<Map<String, dynamic>> responseData = await compute(_isolateJsonDecodeList, response.body);
          if (responseData.isNotEmpty) {
            final scheduleRecord = responseData.first;
            final List<dynamic> rawClassesList = scheduleRecord['ScheduleLists'] ?? scheduleRecord['schedule_lists'] ?? [];
            final List<Map<String, dynamic>> typedList = rawClassesList.map((e) => Map<String, dynamic>.from(e)).toList();

            await _saveScheduleToCache(groupName, typedList);
            _distributeClasses(typedList);
            weeklySuccess = true;
          } else {
            _distributeClasses([]); 
            weeklySuccess = true;
          }
        }
      } on SocketException catch (_) {
        debugPrint("⚠️ Live schedule sync failed: No Internet Connection");
      } on TimeoutException catch (_) {
        debugPrint("⚠️ Live schedule sync failed: Connection Timeout");
      } catch (e) {
        debugPrint("⚠️ Live schedule sync failed: $e");
      }
    } else {
      // Flag as successful if we actively verified the user is intentionally Unassigned
      weeklySuccess = true;
    }

    // 💡 Task 2: Sync Monthly Calendar Events regardless of group subscription
    try {
      final url = Uri.parse('${AuthService.apiBaseUrl}/api/schedule/fetch?department=Calendar&semester=Events');
      
      // 💡 SECURE BACKEND CALL WITH TIMEOUT
      final response = await http.get(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<Map<String, dynamic>> calendarResponse = await compute(_isolateJsonDecodeList, response.body);
        if (calendarResponse.isNotEmpty) {
          await _saveMonthlyCalendarToCache(calendarResponse);
          _indexMonthlyEvents(calendarResponse);
          calendarSuccess = true;
        }
      }
    } on SocketException catch (_) {
      debugPrint("⚠️ Live monthly calendar sync failed: No Internet Connection");
    } on TimeoutException catch (_) {
      debugPrint("⚠️ Live monthly calendar sync failed: Connection Timeout");
    } catch (e) {
      debugPrint("⚠️ Live monthly calendar sync failed: $e");
    }

    // Wrap Up UI State Updates
    if (mounted) {
      setState(() { _isLoading = false; });
      if (weeklySuccess || calendarSuccess) {
        setState(() { _errorMessage = null; });
        if (isManualRefresh) {
          _showOfflineToast('Schedules and Events synchronized successfully!', isError: false);
        }
      } else {
        if (_dailyClasses.values.any((list) => list.isNotEmpty) || _monthlyEvents.isNotEmpty) {
          if (isManualRefresh || isSilentBackgroundSync) {
            _showOfflineToast('Unable to connect to internet. Viewing offline data.', isError: true);
          }
        } else {
          setState(() {
            _errorMessage = "Unable to connect to the server. Please pull down to refresh.";
          });
        }
      }
    }
  }

  void _showOfflineToast(String message, {bool isError = true}) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            EduComponents.icon(context: context, iconData: isError ? EduIcons.danger : EduIcons.success, color: isError ? systemExt.btnDangerText : Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isError ? systemExt.btnDangerText : Colors.white))),
          ],
        ),
        backgroundColor: isError ? systemExt.btnDangerBg : EduDesignTokens.slate900,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
          side: BorderSide(color: isError ? systemExt.btnDangerBorder : Colors.transparent),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  List<DateTime> _generateCalendarDays(DateTime month) {
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    int difference = firstDayOfMonth.weekday - DateTime.monday;
    final startDate = firstDayOfMonth.subtract(Duration(days: difference));
    
    return List.generate(42, (i) => startDate.add(Duration(days: i)));
  }

  void _changeMonth(int increment) {
    setState(() {
      _currentMonthDate = DateTime(_currentMonthDate.year, _currentMonthDate.month + increment, 1);
    });
  }

  void _showDayDetailsModal(DateTime clickedDate) {
    final dateKey = _formatDateToKey(clickedDate);
    final events = _monthlyEvents[dateKey] ?? [];
    final List<String> weekKeys = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    final classes = _dailyClasses[weekKeys[clickedDate.weekday - 1]] ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final textTheme = Theme.of(context).textTheme;
        final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(EduDesignTokens.radius3xl)),
            border: Border(top: BorderSide(color: systemExt.borderNeutral)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: Container(width: 48, height: 4, decoration: BoxDecoration(color: EduDesignTokens.slate300.withOpacity(0.5), borderRadius: BorderRadius.circular(EduDesignTokens.radiusM)))),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${clickedDate.year}-${clickedDate.month.toString().padLeft(2, '0')}-${clickedDate.day.toString().padLeft(2, '0')}", style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('Day Details', style: textTheme.titleLarge),
                    ],
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(EduDesignTokens.radiusFull),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: systemExt.btnSoftBg, shape: BoxShape.circle, border: Border.all(color: systemExt.borderNeutral)),
                      child: EduComponents.icon(context: context, iconData: EduIcons.close, size: 18, color: systemExt.btnSoftText),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24, thickness: 1),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    Text('Weekly Classes', style: textTheme.titleMedium),
                    const SizedBox(height: 12),
                    if (classes.isEmpty)
                      Padding(padding: const EdgeInsets.symmetric(vertical: 16.0), child: Center(child: Text('No classes scheduled for this day.', style: textTheme.bodyMedium)))
                    else
                      ...classes.map((classData) => _buildDetailClassItemCard(classData, clickedDate)),
                    const SizedBox(height: 24),
                    Text('Special / Holidays', style: textTheme.titleMedium),
                    const SizedBox(height: 12),
                    if (events.isEmpty)
                      Padding(padding: const EdgeInsets.symmetric(vertical: 16.0), child: Center(child: Text('No events or holidays scheduled.', style: textTheme.bodyMedium)))
                    else
                      ...events.map((eventData) => _buildHolidayDetailCard(eventData)),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _convertTo12HourRange(String timeRange) {
    try {
      final parts = timeRange.split(' - ');
      if (parts.length != 2) return timeRange;
      String formatTime(String timeStr) {
        final timeParts = timeStr.trim().split(':');
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        final period = hour >= 12 ? 'PM' : 'AM';
        var hour12 = hour % 12;
        if (hour12 == 0) hour12 = 12;
        return '$hour12:${minute.toString().padLeft(2, '0')} $period';
      }
      return '${formatTime(parts[0])} - ${formatTime(parts[1])}';
    } catch (_) { return timeRange; }
  }

  bool _isClassOngoing(String classDay, String timeRange) {
    if (classDay.isEmpty || timeRange.isEmpty) return false;
    final now = DateTime.now();
    final List<String> weekKeys = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    if (classDay.toLowerCase().trim() != weekKeys[now.weekday - 1]) return false;
    try {
      final parts = timeRange.split(' - ');
      final startParts = parts[0].trim().split(':');
      final endParts = parts[1].trim().split(':');
      final currentMinutes = now.hour * 60 + now.minute;
      final startMinutes = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } catch (_) { return false; }
  }

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
      textColor = const Color(0xFF0284C7); // 💡 Safe equivalent for sky600
      iconMark = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F9FF), // 💡 Safe equivalent for sky50
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

  /// Optimistically marks attendance: flips the matched class card instantly
  /// and persists in the background, rolling back with a toast if the write
  /// fails. Avoids waiting on a DB write + cloud push + full week reload
  /// before the card visibly updates.
  Future<void> _handleAttendanceTap({
    required String dateKey,
    required String rawTime,
    required String subject,
    required String targetStatus,
  }) async {
    final String logKey = "$rawTime|$subject";
    final String previousStatus = _weeklyAttendanceLog[dateKey]?[logKey] ?? 'none';

    if (previousStatus == targetStatus) return; // no-op

    // 1. Instant local UI update for this exact class card.
    setState(() {
      final dayMap = _weeklyAttendanceLog.putIfAbsent(dateKey, () => {});
      if (targetStatus == 'none') {
        dayMap.remove(logKey);
      } else {
        dayMap[logKey] = targetStatus;
      }
    });

    // 2. Persist in the background; UI has already moved on.
    try {
      await AttendanceDbService.logAttendance(
        date: dateKey,
        timeSlot: rawTime,
        subject: subject,
        status: targetStatus,
      );
      unawaited(_pushCloudStateSafely());

      // Let other tabs (Home dashboard) know to refresh their own local
      // attendance state — this doesn't force anything heavy on this screen.
      AppStateNotifier.scheduleRefreshNotifier.value =
          AppStateNotifier.scheduleRefreshNotifier.value + 1;
    } catch (e) {
      debugPrint("⚠️ Attendance write failed, rolling back: $e");
      if (!mounted) return;
      setState(() {
        final dayMap = _weeklyAttendanceLog.putIfAbsent(dateKey, () => {});
        if (previousStatus == 'none') {
          dayMap.remove(logKey);
        } else {
          dayMap[logKey] = previousStatus;
        }
      });
      _showOfflineToast('Could not save attendance. Please try again.', isError: true);
    }
  }

  /// Background-only cloud push; failures are logged, not surfaced, since
  /// the local DB write (source of truth for the UI) already succeeded.
  Future<void> _pushCloudStateSafely() async {
    try {
      await CloudSyncService.pushState();
    } catch (e) {
      debugPrint("⚠️ Cloud push for attendance failed (will retry on next sync): $e");
    }
  }

  /// Builds a symmetric control bar to let users easily log class status.
  Widget _buildAttendanceActionBar(Map<String, dynamic> classData, DateTime date, String currentStatus) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final rawTime = classData['time'] ?? '10:00 - 11:00';
    final subject = classData['subject'] ?? 'Unspecified Subject';
    final dateKey = _formatDateToKey(date);

    Widget buildStatusItem({
      required String status,
      required SolarIconData icon,
      required String label,
      required Color activeColor,
      required Color activeBg,
    }) {
      final bool isSelected = currentStatus == status;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            final targetStatus = isSelected ? 'none' : status;
            _handleAttendanceTap(
              dateKey: dateKey,
              rawTime: rawTime.toString(),
              subject: subject,
              targetStatus: targetStatus,
            );
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
                SolarIcon(
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
            icon: SolarIcons.CheckCircle,
            label: 'Attended',
            activeColor: EduDesignTokens.emerald600,
            activeBg: EduDesignTokens.emerald50.withOpacity(0.15),
          ),
          buildStatusItem(
            status: 'missed',
            icon: SolarIcons.CloseCircle,
            label: 'Missed',
            activeColor: EduDesignTokens.rose700,
            activeBg: EduDesignTokens.rose50.withOpacity(0.15),
          ),
          buildStatusItem(
            status: 'cancelled',
            icon: SolarIcons.StopCircle,
            label: 'Cancelled',
            activeColor: const Color(0xFFD97706), // 💡 Safe equivalent for amber600
            activeBg: const Color(0xFFFEF3C7).withOpacity(0.15), // 💡 Safe equivalent for amber50
          ),
          buildStatusItem(
            status: 'holiday',
            icon: SolarIcons.Umbrella,
            label: 'Holiday',
            activeColor: const Color(0xFF0284C7), // 💡 Safe equivalent for sky600
            activeBg: const Color(0xFFF0F9FF).withOpacity(0.15), // 💡 Safe equivalent for sky50
          ),
          buildStatusItem(
            status: 'none',
            icon: SolarIcons.RefreshCircle,
            label: 'Reset',
            activeColor: const Color(0xFF475569), // 💡 Safe equivalent for slate600
            activeBg: EduDesignTokens.slate100.withOpacity(0.15),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailClassItemCard(Map<String, dynamic> classData, DateTime date) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    final rawTime = classData['time'] ?? '10:00 - 11:00';
    final isOngoing = _isClassOngoing(classData['day']?.toString() ?? '', rawTime.toString());

    // Pull attendance logging state for this particular session on this date
    final String currentStatus = _weeklyAttendanceLog[_formatDateToKey(date)]?["${rawTime}|${classData['subject']}"] ?? 'none';

    Color? borderColor;
    Color? cardBgColor = Theme.of(context).cardColor;
    double borderWidth = 1.5;

    if (isOngoing) {
      borderColor = systemExt.borderFocus;
      borderWidth = 2.0;
      cardBgColor = EduDesignTokens.indigo50.withOpacity(0.2);
    } else if (currentStatus == 'attended') {
      borderColor = EduDesignTokens.emerald500.withOpacity(0.4);
    } else if (currentStatus == 'missed') {
      borderColor = EduDesignTokens.rose700.withOpacity(0.4);
    } else if (currentStatus == 'cancelled') {
      borderColor = EduDesignTokens.slate300.withOpacity(0.4);
      cardBgColor = Theme.of(context).cardColor.withOpacity(0.6);
    } else if (currentStatus == 'holiday') {
      borderColor = EduDesignTokens.sky500.withOpacity(0.4);
    } else {
      borderColor = systemExt.borderNeutral;
    }

    return Container(
      key: ValueKey("${_formatDateToKey(date)}_${rawTime}_${classData['subject']}"),
      margin: const EdgeInsets.only(bottom: 12.0),
      child: EduComponents.card(
        context: context,
        child: Container(
          decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
          border: Border.all(color: borderColor, width: borderWidth),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSubjectHeader(
                        classData['subject'] ?? 'Unspecified Subject',
                        currentStatus,
                        textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, height: 1.3, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          EduComponents.icon(context: context, iconData: EduIcons.chevronRight, size: 14, color: EduDesignTokens.slate400),
                          const SizedBox(width: 4),
                          Expanded(child: Text("${classData['room'] ?? 'TBA'}  ·  ${classData['teacher'] ?? 'Unknown Faculty'}", style: textTheme.bodyMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: const BoxConstraints(minWidth: 100),
                  decoration: BoxDecoration(
                    color: isOngoing ? EduDesignTokens.indigo50.withOpacity(0.8) : systemExt.btnSoftBg,
                    borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                    border: Border.all(color: isOngoing ? EduDesignTokens.indigo500.withOpacity(0.2) : systemExt.btnSoftBorder),
                  ),
                  child: Text(_convertTo12HourRange(rawTime.toString()).replaceAll(' - ', '\n'), textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isOngoing ? EduDesignTokens.indigo700 : systemExt.btnSoftText, height: 1.3)),
                ),
              ],
            ),
            
            // Symmetrical Interactive Hub Strip
            _buildAttendanceActionBar(classData, date, currentStatus),
          ],
                ),
        ),
      ),
    );
  }

  Widget _buildHolidayDetailCard(Map<String, dynamic> eventData) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: systemExt.btnDangerBg, borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl), border: Border.all(color: systemExt.btnDangerBorder, width: 1.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: EduDesignTokens.rose100.withOpacity(0.3), borderRadius: BorderRadius.circular(EduDesignTokens.radiusM)),
            child: Text((eventData['Type'] ?? 'Holiday').toString().toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: systemExt.btnDangerText, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 10),
          Text(eventData['Title'] ?? 'Holiday', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: systemExt.btnDangerText)),
          const SizedBox(height: 4),
          Text(eventData['Description'] ?? 'No descriptions provided', style: TextStyle(fontSize: 12, color: systemExt.btnDangerText.withOpacity(0.8), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isPageVisible = TickerMode.of(context);
    final textTheme = Theme.of(context).textTheme;
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;

    if (isPageVisible && !_wasPageVisible) {
      _wasPageVisible = true;
      _checkAndResetFocus();
    } else if (!isPageVisible) {
      _wasPageVisible = false;
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: systemExt.pageBackground),
        child: SafeArea(
          child: RefreshIndicator(
            color: Theme.of(context).primaryColor,
            onRefresh: () async {
              await CloudSyncService.bootstrapFromCloud();
              final sub = await AuthService.getSubscribedSchedule();
              final validSub = (sub != null && sub.isNotEmpty) ? sub : null;
              if (mounted) { setState(() { _currentSubscription = validSub; }); }
              await _loadAttendanceLogs(); // Reload local logs
              await _syncAllLiveRecords(validSub, isManualRefresh: true);
              _resetToToday();
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Text('Schedules', style: textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(_currentSubscription == null ? 'Configure section subscription in profile settings' : 'Interactive calendar and examination timetable', style: textTheme.bodyMedium),
                    ]),
                  ),
                ),
                
                // 💡 UI SPLIT: Isolated the Weekly Schedule from the Monthly Calendar
                // This ensures the placeholder takes over ONLY the weekly timeline part
                if (_currentSubscription == null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: _buildNoSubscriptionPlaceholder(),
                    ),
                  )
                else if (_isLoading && _dailyClasses.values.every((list) => list.isEmpty))
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40.0),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (_errorMessage != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: _buildErrorPlaceholder(),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: RepaintBoundary(child: _buildInteractiveScheduleCard()),
                    ),
                  ),

                // 💡 INDEPENDENT: Monthly Calendar always renders below regardless of subscription!
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: RepaintBoundary(child: _buildMonthGridCalendarCard()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthGridCalendarCard() {
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final titleString = "${months[_currentMonthDate.month - 1]} ${_currentMonthDate.year}";
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final textTheme = Theme.of(context).textTheme;
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final List<DateTime> calendarDays = _generateCalendarDays(_currentMonthDate);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < 0) _changeMonth(1);
            if (details.primaryVelocity! > 0) _changeMonth(-1);
          }
        },
        child: EduComponents.card(
          context: context,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Calendar', style: textTheme.titleMedium), const SizedBox(height: 4), Text(titleString, style: textTheme.bodyMedium)]),
                    EduComponents.badge(backgroundColor: systemExt.btnSoftBg, textColor: systemExt.btnSoftText, child: const Text('MONTH VIEW', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 0.5))),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(weekdays.length, (index) => SizedBox(width: 36, child: Text(weekdays[index], textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: index == 6 ? EduDesignTokens.rose700 : EduDesignTokens.slate400)))),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 8, crossAxisSpacing: 8),
                  itemCount: calendarDays.length,
                  itemBuilder: (context, idx) {
                    final dayDate = calendarDays[idx];
                    final isCurrentMonth = dayDate.month == _currentMonthDate.month;
                    final isSunday = dayDate.weekday == DateTime.sunday;
                    final now = DateTime.now();
                    final isToday = dayDate.day == now.day && dayDate.month == now.month && dayDate.year == now.year;
                    final dateKey = _formatDateToKey(dayDate);
                    final hasEvent = _monthlyEvents.containsKey(dateKey) && _monthlyEvents[dateKey]!.isNotEmpty;

                    return InkWell(
                      onTap: () => _showDayDetailsModal(dayDate),
                      borderRadius: BorderRadius.circular(EduDesignTokens.radiusFull),
                      child: Container(
                        decoration: BoxDecoration(color: isToday ? EduDesignTokens.indigo50.withOpacity(0.15) : Colors.transparent, shape: BoxShape.circle, border: isToday ? Border.all(color: Theme.of(context).primaryColor, width: 1.5) : null),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Text(dayDate.day.toString(), style: TextStyle(fontSize: 14, fontWeight: (isToday || isSunday) ? FontWeight.bold : FontWeight.w500, color: isToday ? Theme.of(context).primaryColor : isSunday ? (isCurrentMonth ? EduDesignTokens.rose700 : EduDesignTokens.rose700.withOpacity(0.4)) : isCurrentMonth ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : EduDesignTokens.slate900) : EduDesignTokens.slate300)),
                            if (hasEvent) Positioned(bottom: 4, child: Container(width: 4, height: 4, decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle))),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInteractiveScheduleCard() {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: EduComponents.card(
        context: context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Weekly Timetable', style: textTheme.titleMedium), const SizedBox(height: 4), Text('Section: ${_currentSubscription ?? "Unspecified"}', style: textTheme.bodyMedium?.copyWith(fontSize: 12))]),
                  EduComponents.badge(backgroundColor: EduDesignTokens.indigo50.withOpacity(0.8), textColor: EduDesignTokens.indigo700, child: const Text('WEEK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SmoothDaySelector(
                pageController: _pageController,
                dayNames: _dayShortNames,
                activeIndex: _activeDayIndex,
                onTap: (index) {
                  setState(() { _activeDayIndex = index; });
                  _pageController.animateToPage(index, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
                },
              ),
            ),
            const Divider(height: 24, thickness: 1),
            SizedBox(
              height: 420, // 💡 Slightly height expanded to offer zero viewport-clipping
              child: PageView.builder(
                controller: _pageController,
                itemCount: _dbDayKeys.length,
                onPageChanged: (index) { setState(() { _activeDayIndex = index; }); },
                itemBuilder: (context, dayIndex) => DayClassesListKeepAlive(
                  dayShort: _dayShortNames[dayIndex],
                  classesList: _dailyClasses[_dbDayKeys[dayIndex]] ?? [],
                  cardBuilder: (classData) => _buildDetailClassItemCard(classData, _getDateOfThisWeek(dayIndex)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSubscriptionPlaceholder() {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: EduComponents.card(
        context: context,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48.0, horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: EduDesignTokens.indigo50.withOpacity(0.15), shape: BoxShape.circle), child: EduComponents.icon(context: context, iconData: EduIcons.attendanceInactive, color: Theme.of(context).primaryColor, size: 40)),
              const SizedBox(height: 20),
              Text('No Section Subscribed', textAlign: TextAlign.center, style: textTheme.titleMedium),
              const SizedBox(height: 8),
              Text("Please go to Profile tab and choose your weekly schedule block to load your class routine.", textAlign: TextAlign.center, style: textTheme.bodyMedium?.copyWith(height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder() {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: EduComponents.card(
        context: context,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48.0, horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: EduDesignTokens.rose100.withOpacity(0.15), shape: BoxShape.circle), child: EduComponents.icon(context: context, iconData: EduIcons.danger, color: EduDesignTokens.rose700, size: 40)),
              const SizedBox(height: 20),
              Text('Connection Required', textAlign: TextAlign.center, style: textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center, style: textTheme.bodyMedium?.copyWith(height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}

class SmoothDaySelector extends StatelessWidget {
  final PageController pageController;
  final List<String> dayNames;
  final int activeIndex;
  final ValueChanged<int> onTap;

  const SmoothDaySelector({super.key, required this.pageController, required this.dayNames, required this.activeIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: systemExt.btnSoftBg, borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl), border: Border.all(color: systemExt.borderNeutral)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / dayNames.length;
          return AnimatedBuilder(
            animation: pageController,
            builder: (context, child) {
              double page = pageController.hasClients ? (pageController.page ?? activeIndex.toDouble()) : activeIndex.toDouble();
              return Stack(
                children: [
                  Positioned(left: page * tabWidth, top: 0, bottom: 0, width: tabWidth, child: Container(decoration: BoxDecoration(color: EduDesignTokens.indigo50.withOpacity(0.15), borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl), border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.3))))),
                  Row(
                    children: List.generate(dayNames.length, (index) {
                      final textColor = Color.lerp(EduDesignTokens.slate400, Theme.of(context).primaryColor, (1.0 - (page - index).abs()).clamp(0.0, 1.0))!;
                      return Expanded(child: GestureDetector(onTap: () => onTap(index), behavior: HitTestBehavior.opaque, child: Center(child: Text(dayNames[index], style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor)))));
                    }),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class DayClassesListKeepAlive extends StatefulWidget {
  final String dayShort;
  final List<Map<String, dynamic>> classesList;
  final Widget Function(Map<String, dynamic>) cardBuilder;

  const DayClassesListKeepAlive({super.key, required this.dayShort, required this.classesList, required this.cardBuilder});

  @override
  State<DayClassesListKeepAlive> createState() => _DayClassesListKeepAliveState();
}

class _DayClassesListKeepAliveState extends State<DayClassesListKeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final textTheme = Theme.of(context).textTheme;

    if (widget.classesList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            EduComponents.icon(context: context, iconData: EduIcons.attendanceInactive, size: 48, color: EduDesignTokens.slate300),
            const SizedBox(height: 12),
            Text('No Classes Scheduled', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Enjoy your self-study day!', style: textTheme.bodyMedium),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(widget.dayShort, style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)), Text('${widget.classesList.length} classes', style: textTheme.bodyMedium)])),
        const SizedBox(height: 8),
        Expanded(child: ListView.builder(padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0), physics: const ClampingScrollPhysics(), itemCount: widget.classesList.length, itemBuilder: (context, index) => widget.cardBuilder(widget.classesList[index]))),
      ],
    );
  }
}