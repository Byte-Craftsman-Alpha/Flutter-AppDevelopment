import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../constants/theme.dart'; // Handles your centralized custom icons, tokens, and widgets

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final PageController _pageController = PageController();
  int _activeDayIndex = 0; // Monday = 0, Tuesday = 1, etc.
  bool _isLoading = false;
  String? _errorMessage;
  String? _currentSubscription;

  // Active Month Tracker for Month Calendar card
  late DateTime _currentMonthDate;
  
  // Track visibility to auto-reset when returning to this page
  bool _wasPageVisible = false;

  // Days of the week structures
  final List<String> _dayShortNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  // ignore: unused_field
  final List<String> _dayFullNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  final List<String> _dbDayKeys = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];

  // Timetable container split by weekday key
  final Map<String, List<Map<String, dynamic>>> _dailyClasses = {
    'monday': [],
    'tuesday': [],
    'wednesday': [],
    'thursday': [],
    'friday': [],
    'saturday': [],
  };

  // Monthly Calendar events indexed by "YYYY-MM-DD"
  final Map<String, List<Map<String, dynamic>>> _monthlyEvents = {};

  @override
  void initState() {
    super.initState();
    _currentMonthDate = DateTime.now();
    _loadInitialSubscriptionAndData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // 💡 Async check to load schedule preferences on app initialization
  Future<void> _loadInitialSubscriptionAndData() async {
    final sub = await AuthService.getSubscribedSchedule();
    if (mounted) {
      setState(() {
        _currentSubscription = sub;
      });
    }
    if (sub != null) {
      _initializeScheduleAndCalendar(sub);
    }
  }

  // 💡 Safe parsing of standard DateTime keys
  String _formatDateToKey(DateTime date) {
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return "$year-$month-$day";
  }

  // 💡 Reset page views and month indices to Current Day and Current Month
  void _resetToToday() {
    final now = DateTime.now();
    final weekdayIndex = now.weekday; // Monday = 1, Saturday = 6, Sunday = 7
    int targetPage = 0;
    if (weekdayIndex >= 1 && weekdayIndex <= 6) {
      targetPage = weekdayIndex - 1; // Mon = 0, Sat = 5
    }

    setState(() {
      _currentMonthDate = now;
      _activeDayIndex = targetPage;
    });

    // Animate viewports smoothly to the active weekday card
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(targetPage);
      }
    });
  }

  // 💡 Checks subscription changes and resets focus when tab changes
  Future<void> _checkAndResetFocus() async {
    _resetToToday();
    
    // Check if subscription changed while user was on another screen
    final latestSub = await AuthService.getSubscribedSchedule();
    if (latestSub != _currentSubscription) {
      if (mounted) {
        setState(() {
          _currentSubscription = latestSub;
        });
      }
      if (latestSub != null) {
        _initializeScheduleAndCalendar(latestSub);
      }
    }
  }

  // 💡 Persist retrieved Monthly Calendar items to cache
  Future<void> _saveMonthlyCalendarToCache(List<Map<String, dynamic>> eventsList) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('offline_cache_monthly_calendar', json.encode(eventsList));
    } catch (e) {
      debugPrint("❌ Failed to cache Monthly Calendar data: $e");
    }
  }

  // 💡 Load persistent Monthly Calendar items from cache
  Future<List<Map<String, dynamic>>?> _loadMonthlyCalendarFromCache() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString('offline_cache_monthly_calendar');
      if (jsonStr != null) {
        final List<dynamic> decoded = json.decode(jsonStr);
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint("❌ Failed to parse cached Monthly Calendar: $e");
    }
    return null;
  }

  // 💡 Persistently cache a group's schedule list locally to disk
  Future<void> _saveScheduleToCache(String groupName, List<Map<String, dynamic>> classesList) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('offline_cache_schedule_$groupName', json.encode(classesList));
    } catch (e) {
      debugPrint("❌ Failed to write local schedule disk cache: $e");
    }
  }

  // 💡 Fetch a group's cached schedule from local storage
  Future<List<Map<String, dynamic>>?> _loadScheduleFromCache(String groupName) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString('offline_cache_schedule_$groupName');
      if (jsonStr != null) {
        final List<dynamic> decoded = json.decode(jsonStr);
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint("❌ Failed to parse local schedule disk cache: $e");
    }
    return null;
  }

  // 💡 Global Initializer: loads caches first then triggers silent background synchronization
  Future<void> _initializeScheduleAndCalendar(String groupName) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // 1. Fetch from offline cache first (Instant rendering!)
    final cachedClasses = await _loadScheduleFromCache(groupName);
    final cachedCalendar = await _loadMonthlyCalendarFromCache();

    if (cachedClasses != null) {
      _distributeClasses(cachedClasses);
    }
    if (cachedCalendar != null) {
      _indexMonthlyEvents(cachedCalendar);
    }

    if (cachedClasses != null || cachedCalendar != null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      // Silently sync the database background records to keep it fresh
      _syncAllLiveRecords(groupName, isSilentBackgroundSync: true);
    } else {
      // First-run loading sequence with no existing caches
      await _syncAllLiveRecords(groupName, isSilentBackgroundSync: false);
    }
  }

  // 💡 Index monthly calendar events for O(1) instant key lookup matching
  void _indexMonthlyEvents(List<Map<String, dynamic>> rawEventsList) {
    _monthlyEvents.clear();
    for (var item in rawEventsList) {
      final rawDate = item['Date']?.toString() ?? ''; // e.g. "2026-06-25"
      if (rawDate.isNotEmpty) {
        if (!_monthlyEvents.containsKey(rawDate)) {
          _monthlyEvents[rawDate] = [];
        }
        _monthlyEvents[rawDate]!.add(item);
      }
    }
  }

  // 💡 Distributes classes and sorts them chronologically
  void _distributeClasses(List<Map<String, dynamic>> rawClassesList) {
    // Clear previous schedule data
    for (var key in _dailyClasses.keys) {
      _dailyClasses[key] = [];
    }

    // Distribute incoming classes to their respective days
    for (var item in rawClassesList) {
      final String day = (item['day'] ?? '').toString().toLowerCase().trim();
      if (_dailyClasses.containsKey(day)) {
        _dailyClasses[day]!.add(item);
      }
    }

    // Sort day lists by their class hour sequence
    for (var dayKey in _dailyClasses.keys) {
      _dailyClasses[dayKey]!.sort((a, b) {
        final timeA = (a['time'] ?? '').toString();
        final timeB = (b['time'] ?? '').toString();
        return timeA.compareTo(timeB);
      });
    }

    // Match index to current day of the week (Monday to Saturday)
    final weekdayIndex = DateTime.now().weekday; // Monday = 1, Saturday = 6
    int targetPage = 0;
    if (weekdayIndex >= 1 && weekdayIndex <= 6) {
      targetPage = weekdayIndex - 1; // Align Mon = 0, Sat = 5
    }

    _activeDayIndex = targetPage;
    
    // Jump to the current weekday inside PageView viewports
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(targetPage);
      }
    });
  }

  // 💡 Syncs BOTH table structures (Weekly Schedules & Monthly Calendar) simultaneously
  Future<void> _syncAllLiveRecords(
    String groupName, {
    bool isSilentBackgroundSync = false,
    bool isManualRefresh = false,
  }) async {
    if (!isSilentBackgroundSync && !isManualRefresh) {
      setState(() {
        _isLoading = true;
      });
    }

    bool weeklySuccess = false;
    bool calendarSuccess = false;

    // 1. Fetch Weekly Schedule
    try {
      final List<dynamic> response = await Supabase.instance.client
          .from('Weekly Schedules')
          .select()
          .eq('ScheduleGroupName', groupName);

      if (response.isNotEmpty) {
        final scheduleRecord = response.first;
        final List<dynamic> rawClassesList = scheduleRecord['ScheduleLists'] ?? [];
        final List<Map<String, dynamic>> typedList = rawClassesList.map((e) => Map<String, dynamic>.from(e)).toList();

        await _saveScheduleToCache(groupName, typedList);
        _distributeClasses(typedList);
        weeklySuccess = true;
      }
    } catch (e) {
      debugPrint("⚠️ Live schedule sync failed: $e");
    }

    // 2. Fetch Monthly Calendar Events
    try {
      final List<dynamic> calendarResponse = await Supabase.instance.client
          .from('Monthly Calendar')
          .select();

      if (calendarResponse.isNotEmpty) {
        final List<Map<String, dynamic>> typedCalendarList = calendarResponse.map((e) => Map<String, dynamic>.from(e)).toList();
        await _saveMonthlyCalendarToCache(typedCalendarList);
        _indexMonthlyEvents(typedCalendarList);
        calendarSuccess = true;
      }
    } catch (e) {
      debugPrint("⚠️ Live monthly calendar sync failed: $e");
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (weeklySuccess && calendarSuccess) {
        setState(() {
          _errorMessage = null;
        });
        if (isManualRefresh) {
          _showOfflineToast('Schedules and Events synchronized successfully!', isError: false);
        }
      } else {
        // If background update failed but cached data is already drawn, keep playing the cache
        if (_dailyClasses.values.any((list) => list.isNotEmpty) || _monthlyEvents.isNotEmpty) {
          if (isManualRefresh || isSilentBackgroundSync) {
            _showOfflineToast('Unable to refresh schedule. Playing offline cached schedule.', isError: true);
          }
        } else {
          // Hard loader exception (First launch with zero cache + network drop)
          setState(() {
            _errorMessage = "Unable to connect to the server. Please check your connection and pull down to refresh.";
          });
        }
      }
    }
  }

  // 💡 Modern, clean floating Toast SnackBar styled strictly with Theme Tokens
  void _showOfflineToast(String message, {bool isError = true}) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            EduComponents.icon(
              context: context,
              iconData: isError ? EduIcons.danger : EduIcons.success,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? systemExt.btnDangerBg : EduDesignTokens.slate900,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
          side: BorderSide(color: isError ? systemExt.btnDangerBorder : Colors.transparent),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // 💡 Generate robust calendar grids covering pad boundaries
  List<DateTime> _generateCalendarDays(DateTime month) {
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    int difference = firstDayOfMonth.weekday - DateTime.monday;
    final startDate = firstDayOfMonth.subtract(Duration(days: difference));
    
    List<DateTime> days = [];
    for (int i = 0; i < 42; i++) {
      days.add(startDate.add(Duration(days: i)));
    }
    return days;
  }

  // 💡 Shift month index dynamically
  void _changeMonth(int increment) {
    setState(() {
      _currentMonthDate = DateTime(_currentMonthDate.year, _currentMonthDate.month + increment, 1);
    });
  }

  // 💡 Slide up detail modal when calendar date cells are clicked (matching design rules)
  void _showDayDetailsModal(DateTime clickedDate) {
    final dateKey = _formatDateToKey(clickedDate);
    final events = _monthlyEvents[dateKey] ?? [];
    
    // Resolve weekday text identifier to match classes list
    final List<String> weekKeys = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    final weekdayKey = weekKeys[clickedDate.weekday - 1];
    final classes = _dailyClasses[weekdayKey] ?? [];

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
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top drag indicator block
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: EduDesignTokens.slate300.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(EduDesignTokens.radiusM),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Custom Header Row matching visual specification
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDateToDisplayString(clickedDate),
                        style: textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Day Details',
                        style: textTheme.titleLarge,
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(EduDesignTokens.radiusFull),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: systemExt.btnSoftBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: systemExt.borderNeutral),
                      ),
                      child: EduComponents.icon(
                        context: context, 
                        iconData: EduIcons.close, 
                        size: 18, 
                        color: systemExt.btnSoftText
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24, thickness: 1),

              // Scrollable day events and timetable lists
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // Section 1: Weekly Classes
                    Text(
                      'Weekly Classes',
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    if (classes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        child: Center(
                          child: Text(
                            'No classes scheduled for this day.',
                            style: textTheme.bodyMedium,
                          ),
                        ),
                      )
                    else
                      ...classes.map((classData) => _buildDetailClassItemCard(classData)),
                      
                    const SizedBox(height: 24),

                    // Section 2: Special / Holidays
                    Text(
                      'Special / Holidays',
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    if (events.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        child: Center(
                          child: Text(
                            'No events or holidays scheduled.',
                            style: textTheme.bodyMedium,
                          ),
                        ),
                      )
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

  // 💡 Formats date objects to header strings: e.g. "2026-06-25"
  String _formatDateToDisplayString(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  // 💡 Helper to convert 24 hour string "HH:mm - HH:mm" to 12 hour string "hh:mm AM/PM - hh:mm AM/PM"
  String _convertTo12HourRange(String timeRange) {
    try {
      final parts = timeRange.split(' - ');
      if (parts.length != 2) return timeRange;

      String formatTime(String timeStr) {
        final timeParts = timeStr.trim().split(':');
        if (timeParts.length < 2) return timeStr;
        final hour = int.tryParse(timeParts[0]);
        final minute = int.tryParse(timeParts[1]);
        if (hour == null || minute == null) return timeStr;

        final period = hour >= 12 ? 'PM' : 'AM';
        var hour12 = hour % 12;
        if (hour12 == 0) hour12 = 12;

        final minStr = minute.toString().padLeft(2, '0');
        return '$hour12:$minStr $period';
      }

      return '${formatTime(parts[0])} - ${formatTime(parts[1])}';
    } catch (e) {
      return timeRange;
    }
  }

  // 💡 Helper to detect if a specific class is currently active/ongoing (LIVE)
  bool _isClassOngoing(String classDay, String timeRange) {
    if (classDay.isEmpty || timeRange.isEmpty) return false;
    
    final now = DateTime.now();
    final List<String> weekKeys = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    final currentDayKey = weekKeys[now.weekday - 1];
    
    // Check if the scheduled class day matches today's weekday
    if (classDay.toLowerCase().trim() != currentDayKey) return false;
    
    try {
      final parts = timeRange.split(' - ');
      if (parts.length != 2) return false;

      final startParts = parts[0].trim().split(':');
      final endParts = parts[1].trim().split(':');
      if (startParts.length < 2 || endParts.length < 2) return false;

      final startHour = int.tryParse(startParts[0]);
      final startMin = int.tryParse(startParts[1]);
      final endHour = int.tryParse(endParts[0]);
      final endMin = int.tryParse(endParts[1]);

      if (startHour == null || startMin == null || endHour == null || endMin == null) return false;

      // Convert current time and schedule range to pure minutes since midnight to safely support cross-hour slots
      final currentMinutes = now.hour * 60 + now.minute;
      final startMinutes = startHour * 60 + startMin;
      final endMinutes = endHour * 60 + endMin;

      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } catch (e) {
      return false;
    }
  }

  // 💡 Build class cards for Day details popup - Features Live Highlights
  Widget _buildDetailClassItemCard(Map<String, dynamic> classData) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    final subject = classData['subject'] ?? 'Unspecified Subject';
    final room = classData['room'] ?? 'TBA';
    final teacher = classData['teacher'] ?? 'Unknown Faculty';
    final rawTime = classData['time'] ?? '10:00 - 11:00';
    final classDay = classData['day']?.toString() ?? '';
    
    // Parse to student-friendly 12 hour AM/PM representation
    final time12H = _convertTo12HourRange(rawTime.toString());
    final formattedTime = time12H.replaceAll(' - ', '\n');

    // 💡 LIVE Check: Match time range to current time
    final isOngoing = _isClassOngoing(classDay, rawTime.toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      decoration: BoxDecoration(
        color: isOngoing 
            ? EduDesignTokens.indigo50.withOpacity(0.15) 
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
        border: Border.all(
          color: isOngoing ? systemExt.borderFocus : systemExt.borderNeutral, 
          width: isOngoing ? 2.0 : 1.5,
        ),
        boxShadow: isOngoing ? systemExt.cardHoverShadow : systemExt.cardBaseShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    EduComponents.icon(
                      context: context,
                      iconData: EduIcons.chevronRight,
                      size: 14,
                      color: EduDesignTokens.slate400,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '$room  ·  $teacher',
                        style: textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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
              border: Border.all(
                color: isOngoing ? EduDesignTokens.indigo500.withOpacity(0.2) : systemExt.btnSoftBorder,
              ),
            ),
            child: Text(
              formattedTime,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isOngoing ? EduDesignTokens.indigo700 : systemExt.btnSoftText,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 💡 Build holiday cards with the soft pink themed border layout (Dark Mode Optimized)
  Widget _buildHolidayDetailCard(Map<String, dynamic> eventData) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final title = eventData['Title'] ?? 'Holiday';
    final description = eventData['Description'] ?? 'No descriptions provided';
    final type = (eventData['Type'] ?? 'Holiday').toString().toUpperCase();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: systemExt.btnDangerBg, 
        borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
        border: Border.all(color: systemExt.btnDangerBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: EduDesignTokens.rose100.withOpacity(0.3),
              borderRadius: BorderRadius.circular(EduDesignTokens.radiusM),
            ),
            child: Text(
              type,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: systemExt.btnDangerText,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: systemExt.btnDangerText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              color: systemExt.btnDangerText.withOpacity(0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 💡 TickerMode tracker: automatically resets schedules when user switches tabs back to this page
    final bool isPageVisible = TickerMode.of(context);
    final textTheme = Theme.of(context).textTheme;
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;

    if (isPageVisible && !_wasPageVisible) {
      _wasPageVisible = true;
      _checkAndResetFocus(); // Synchronous check replaces slow FutureBuilder!
    } else if (!isPageVisible) {
      _wasPageVisible = false;
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: systemExt.pageBackground,
        ),
        child: SafeArea(
          child: RefreshIndicator(
            color: Theme.of(context).primaryColor,
            // Pull to refresh trigger resets both local views to today, then refreshes both Monthly Calendar & Weekly Schedules
            onRefresh: () async {
              _resetToToday(); // Bring back to current day and month immediately (Even on sync failure)
              
              // 💡 Fetch the absolute latest choice from local storage before calling the sync engine
              final latestSub = await AuthService.getSubscribedSchedule();
              if (latestSub != null) {
                if (mounted) {
                  setState(() {
                    _currentSubscription = latestSub;
                  });
                }
                await _syncAllLiveRecords(latestSub, isManualRefresh: true);
              }
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // Header text title block (App bar duplicate eliminated)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Schedules',
                        style: textTheme.titleLarge?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentSubscription == null 
                            ? 'Configure your section subscription in your Profile settings'
                            : 'Interactive calendar and examination timetable',
                        style: textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                
                _currentSubscription == null
                    ? _buildNoSubscriptionPlaceholder()
                    : _isLoading
                        ? Container(
                            height: 350,
                            alignment: Alignment.center,
                            child: CircularProgressIndicator(color: Theme.of(context).primaryColor),
                          )
                        : _errorMessage != null
                            ? _buildErrorPlaceholder()
                            : Column(
                                children: [
                                  RepaintBoundary(
                                    child: _buildInteractiveScheduleCard(), // 💡 Render first
                                  ),
                                  const SizedBox(height: 12),
                                  RepaintBoundary(
                                    child: _buildMonthGridCalendarCard(), // 💡 Render second
                                  ),
                                  const SizedBox(height: 24),
                                ],
                              ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 💡 Renders the swipe-enabled Mini Month Calendar card (Adaptive Surface)
  Widget _buildMonthGridCalendarCard() {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June', 
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final titleString = "${months[_currentMonthDate.month - 1]} ${_currentMonthDate.year}";
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final textTheme = Theme.of(context).textTheme;
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;

    // Generate date sequence list
    final List<DateTime> calendarDays = _generateCalendarDays(_currentMonthDate);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GestureDetector(
        // Tracking horizontal drag velocity to swipe left/right between months smoothly
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < 0) {
              _changeMonth(1); // Swipe Left -> Next Month
            } else if (details.primaryVelocity! > 0) {
              _changeMonth(-1); // Swipe Right -> Previous Month
            }
          }
        },
        child: EduComponents.card(
          context: context,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Month Indicator Title Row block
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Calendar',
                          style: textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          titleString,
                          style: textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    EduComponents.badge(
                      backgroundColor: systemExt.btnSoftBg,
                      textColor: systemExt.btnSoftText,
                      child: const Text(
                        'MONTH VIEW',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 9,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Calendar Days of Week headers Mon to Sun
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(weekdays.length, (index) {
                    final day = weekdays[index];
                    final isSundayHeader = index == 6; // Sunday column header
                    return SizedBox(
                      width: 36,
                      child: Text(
                        day,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSundayHeader ? EduDesignTokens.rose700 : EduDesignTokens.slate400, // Highlight Sunday Header
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),

                // Days Grid matrix
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: calendarDays.length,
                  itemBuilder: (context, idx) {
                    final dayDate = calendarDays[idx];
                    final isCurrentMonth = dayDate.month == _currentMonthDate.month;
                    final isSunday = dayDate.weekday == DateTime.sunday;
                    
                    // Highlight Current Date (Today)
                    final now = DateTime.now();
                    final isToday = dayDate.day == now.day && 
                                    dayDate.month == now.month && 
                                    dayDate.year == now.year;

                    // Check if this date key has active events in database
                    final dateKey = _formatDateToKey(dayDate);
                    final hasEvent = _monthlyEvents.containsKey(dateKey) && _monthlyEvents[dateKey]!.isNotEmpty;

                    return InkWell(
                      onTap: () => _showDayDetailsModal(dayDate),
                      borderRadius: BorderRadius.circular(EduDesignTokens.radiusFull),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isToday ? EduDesignTokens.indigo50.withOpacity(0.15) : Colors.transparent,
                          shape: BoxShape.circle,
                          border: isToday 
                              ? Border.all(color: Theme.of(context).primaryColor, width: 1.5)
                              : null,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Text(
                              dayDate.day.toString(),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: (isToday || isSunday) ? FontWeight.bold : FontWeight.w500,
                                color: isToday
                                    ? Theme.of(context).primaryColor
                                    : isSunday
                                        ? (isCurrentMonth
                                            ? EduDesignTokens.rose700 // Strong rose red for active month Sunday
                                            : EduDesignTokens.rose700.withOpacity(0.4)) // Dimmed rose red for inactive month Sunday
                                        : isCurrentMonth
                                            ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : EduDesignTokens.slate900)
                                            : EduDesignTokens.slate300,
                              ),
                            ),
                            // Highlight dot if an event exists
                            if (hasEvent)
                              Positioned(
                                bottom: 4,
                                child: Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
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

  // 💡 Renders the swipe-enabled Weekly Schedules card (Adaptive Surface)
  Widget _buildInteractiveScheduleCard() {
    final textTheme = Theme.of(context).textTheme;
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: EduComponents.card(
        context: context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Inner header row
            Padding(
              padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Weekly Timetable',
                        style: textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Section: ${_currentSubscription ?? "Unspecified"}',
                        style: textTheme.bodyMedium?.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                  EduComponents.badge(
                    backgroundColor: EduDesignTokens.indigo50.withOpacity(0.8),
                    textColor: EduDesignTokens.indigo700,
                    child: const Text(
                      'WEEK',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 💡 Smooth Synced Day Selector header block Mon to Sat
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SmoothDaySelector(
                pageController: _pageController,
                dayNames: _dayShortNames,
                activeIndex: _activeDayIndex,
                onTap: (index) {
                  setState(() {
                    _activeDayIndex = index;
                  });
                  _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              ),
            ),
            const Divider(height: 24, thickness: 1),

            // Horizontal swipe view lists
            SizedBox(
              height: 360,
              child: PageView.builder(
                controller: _pageController,
                itemCount: _dbDayKeys.length,
                onPageChanged: (index) {
                  setState(() {
                    _activeDayIndex = index;
                  });
                },
                itemBuilder: (context, dayIndex) {
                  final dayKey = _dbDayKeys[dayIndex];
                  final classes = _dailyClasses[dayKey] ?? [];
                  // Using our custom StateKeepAlive wrapper to keep views cached at 60 FPS
                  return DayClassesListKeepAlive(
                    dayShort: _dayShortNames[dayIndex],
                    classesList: classes,
                    cardBuilder: (classData) => _buildDetailClassItemCard(classData),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSubscriptionPlaceholder() {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(32.0),
      height: 400,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: EduDesignTokens.indigo50.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: EduComponents.icon(
              context: context, 
              iconData: EduIcons.attendanceInactive, 
              color: Theme.of(context).primaryColor, 
              size: 40
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No Section Subscribed',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            "Please go to your Profile tab and choose your weekly schedule block (e.g., Section A or Section B) to load your class routine details.",
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorPlaceholder() {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 64.0),
      height: 400,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: EduDesignTokens.rose100.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: EduComponents.icon(
              context: context, 
              iconData: EduIcons.danger, 
              color: EduDesignTokens.rose700, 
              size: 40
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Connection Required',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 12),
          Text(
            'Or swipe down on this screen to retry.',
            style: textTheme.bodyMedium?.copyWith(
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// 💡 Synced sliding indicator driving day header highlights at 60 FPS in real-time
class SmoothDaySelector extends StatelessWidget {
  final PageController pageController;
  final List<String> dayNames;
  final int activeIndex;
  final ValueChanged<int> onTap;

  const SmoothDaySelector({
    super.key,
    required this.pageController,
    required this.dayNames,
    required this.activeIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: systemExt.btnSoftBg, // Slate container track matches active context theme
        borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
        border: Border.all(color: systemExt.borderNeutral),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final tabWidth = totalWidth / dayNames.length;

          return AnimatedBuilder(
            animation: pageController,
            builder: (context, child) {
              // Read live scroll progress offset
              double page = pageController.hasClients 
                  ? (pageController.page ?? activeIndex.toDouble())
                  : activeIndex.toDouble();

              return Stack(
                children: [
                  // Smoothly interpolating sliding capsule background
                  Positioned(
                    left: page * tabWidth,
                    top: 0,
                    bottom: 0,
                    width: tabWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: EduDesignTokens.indigo50.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                        border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.3), width: 1),
                      ),
                    ),
                  ),
                  
                  // Label rows receiving exact color interpolation updates
                  Row(
                    children: List.generate(dayNames.length, (index) {
                      final distance = (page - index).abs();
                      final isSelectedRatio = (1.0 - distance).clamp(0.0, 1.0);
                      
                      // Lerp colors seamlessly based on swipe displacement ratios
                      final textColor = Color.lerp(
                        EduDesignTokens.slate400, // Deselected grey
                        Theme.of(context).primaryColor, // Subscribed indigo
                        isSelectedRatio,
                      )!;

                      return Expanded(
                        child: GestureDetector(
                          onTap: () => onTap(index),
                          behavior: HitTestBehavior.opaque,
                          child: Center(
                            child: Text(
                              dayNames[index],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ),
                        ),
                      );
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

// 💡 Horizontal Page View Caching Wrapper - Prevents Frame drops entirely!
class DayClassesListKeepAlive extends StatefulWidget {
  final String dayShort;
  final List<Map<String, dynamic>> classesList;
  final Widget Function(Map<String, dynamic>) cardBuilder;

  const DayClassesListKeepAlive({
    super.key,
    required this.dayShort,
    required this.classesList,
    required this.cardBuilder,
  });

  @override
  State<DayClassesListKeepAlive> createState() => _DayClassesListKeepAliveState();
}

class _DayClassesListKeepAliveState extends State<DayClassesListKeepAlive> 
    with AutomaticKeepAliveClientMixin {
    
  @override
  bool get wantKeepAlive => true; // Forces page view caching

  @override
  Widget build(BuildContext context) {
    super.build(context); // Essential registration
    final textTheme = Theme.of(context).textTheme;

    if (widget.classesList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            EduComponents.icon(
              context: context, 
              iconData: EduIcons.attendanceInactive, 
              size: 48, 
              color: EduDesignTokens.slate300
            ),
            const SizedBox(height: 12),
            Text(
              'No Classes Scheduled',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Enjoy your self-study day!',
              style: textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.dayShort,
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${widget.classesList.length} classes',
                style: textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0),
            physics: const ClampingScrollPhysics(), // High performance clamping bounds
            itemCount: widget.classesList.length,
            itemBuilder: (context, index) {
              final classData = widget.classesList[index];
              return widget.cardBuilder(classData);
            },
          ),
        ),
      ],
    );
  }
}