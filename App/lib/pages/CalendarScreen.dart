import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutty_solar_icons/flutty_solar_icons.dart';

import '../services/auth_service.dart';
import '../constants/theme.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final PageController _pageController;
  int _activeDayIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;
  String? _currentSubscription;

  late DateTime _currentDate;
  
  // Storage for standard weekly classes
  final Map<String, List<dynamic>> _weeklySchedule = {
    'monday': [], 'tuesday': [], 'wednesday': [], 'thursday': [], 'friday': [], 'saturday': []
  };
  
  // Storage for remote daily overrides (cancelled classes, holidays, etc.)
  Map<String, dynamic> _dailyOverrides = {};

  final List<String> _dayShortNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  final List<String> _dbDayKeys = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];

  @override
  void initState() {
    super.initState();
    _currentDate = DateTime.now();
    // Default to today if it's a weekday, otherwise Monday
    _activeDayIndex = (_currentDate.weekday >= 1 && _currentDate.weekday <= 6) ? _currentDate.weekday - 1 : 0;
    _pageController = PageController(initialPage: _activeDayIndex);

    _loadInitialData();
    AppStateNotifier.globalRefreshNotifier.addListener(_syncLiveRecords);
  }

  @override
  void dispose() {
    _pageController.dispose();
    AppStateNotifier.globalRefreshNotifier.removeListener(_syncLiveRecords);
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    _currentSubscription = await AuthService.getSubscribedSchedule();
    if (_currentSubscription == null || _currentSubscription!.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = "You are not subscribed to any schedule group. Update this in your Profile.";
      });
      return;
    }

    await _loadCachedSchedule();
    await _syncLiveRecords();
  }

  Future<void> _loadCachedSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cached_weekly_schedule_$_currentSubscription');
    if (cached != null) {
      try {
        final data = json.decode(cached) as Map<String, dynamic>;
        setState(() {
          for (var key in _dbDayKeys) {
            _weeklySchedule[key] = data[key] ?? [];
          }
        });
      } catch (e) {
        debugPrint("Cache Parse Error: $e");
      }
    }
  }

  /// 💡 Fetches BOTH standard weekly schedule AND today's specific overrides
  Future<void> _syncLiveRecords() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final token = await AuthService.getAuthToken();
      if (token == null || _currentSubscription == null) return;

      // 1. Fetch Weekly Schedule (assuming you have a generic route for this, or relying on cache)
      // Note: If you fetch weekly schedule from supabase, do it here and update _weeklySchedule cache.
      // For brevity, we assume the weekly structure is maintained in _weeklySchedule.

      // 2. Fetch Overrides for the Currently Selected Date
      final targetDate = _calculateDateForActiveIndex();
      final dateStr = DateFormat('yyyy-MM-dd').format(targetDate);
      
      final overrideUrl = Uri.parse(
        'https://flutter-app-development-mu.vercel.app/api/schedule/overrides?group_name=${Uri.encodeComponent(_currentSubscription!)}&date=$dateStr'
      );
      
      final overrideRes = await http.get(overrideUrl).timeout(const Duration(seconds: 10));
      
      if (overrideRes.statusCode == 200) {
        final data = json.decode(overrideRes.body);
        _dailyOverrides = data['overrides'] ?? {};
      }

      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });

    } on SocketException catch (_) {
      setState(() {
        _isLoading = false;
      });
      // Silent fail, relies on offline cache
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint("Schedule Sync Error: $e");
    }
  }

  DateTime _calculateDateForActiveIndex() {
    int currentDayOfWeek = _currentDate.weekday; // 1=Mon, 7=Sun
    int targetDayOfWeek = _activeDayIndex + 1;
    int difference = targetDayOfWeek - currentDayOfWeek;
    return _currentDate.add(Duration(days: difference));
  }

  void _onDaySelected(int index) {
    setState(() {
      _activeDayIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    // Fetch overrides for the newly selected day
    _syncLiveRecords();
  }

  Widget _buildClassCard(Map<String, dynamic> classData) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final textTheme = Theme.of(context).textTheme;

    String time = classData['time'] ?? 'Unknown Time';
    String subject = classData['subject'] ?? 'Unknown Subject';
    String room = classData['room'] ?? 'TBA';
    String teacher = classData['teacher'] ?? '';
    
    // 💡 Override Engine Interception
    bool isCancelled = false;
    String? overrideNote;
    
    if (_dailyOverrides.containsKey(time)) {
      final overrideData = _dailyOverrides[time];
      if (overrideData['status'] == 'cancelled') {
        isCancelled = true;
      }
      if (overrideData['new_subject'] != null) {
        subject = overrideData['new_subject'];
      }
      if (overrideData['new_room'] != null) {
        room = overrideData['new_room'];
      }
      overrideNote = overrideData['note'];
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
        boxShadow: systemExt.cardBaseShadow,
        border: isCancelled 
            ? Border.all(color: systemExt.btnDangerBorder, width: 1.5)
            : Border.all(color: systemExt.borderNeutral),
      ),
      child: Opacity(
        opacity: isCancelled ? 0.7 : 1.0,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded, size: 16, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 6),
                      Text(time, style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                    ],
                  ),
                  if (isCancelled)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: systemExt.btnDangerBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('CANCELLED', style: TextStyle(color: systemExt.btnDangerText, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: EduDesignTokens.slate100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.room, size: 12, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(room, style: TextStyle(color: Colors.grey.shade700, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                subject,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  decoration: isCancelled ? TextDecoration.lineThrough : null,
                ),
              ),
              if (teacher.isNotEmpty && !isCancelled) ...[
                const SizedBox(height: 4),
                Text(teacher, style: textTheme.bodySmall?.copyWith(color: EduDesignTokens.slate500)),
              ],
              if (overrideNote != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: Colors.amber),
                      const SizedBox(width: 8),
                      Expanded(child: Text(overrideNote, style: const TextStyle(fontSize: 12, color: Colors.amber))),
                    ],
                  ),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayView(String dayKey) {
    List<dynamic> classes = _weeklySchedule[dayKey] ?? [];

    if (classes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            EduComponents.icon(context: context, iconData: SolarIcons.Calendar, size: 48, color: EduDesignTokens.slate300),
            const SizedBox(height: 12),
            Text('No Classes Scheduled', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Enjoy your free day!', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _syncLiveRecords,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        itemCount: classes.length,
        itemBuilder: (context, index) {
          return _buildClassCard(classes[index] as Map<String, dynamic>);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Schedule', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _syncLiveRecords,
          )
        ],
      ),
      body: Column(
        children: [
          // Custom Day Selector
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: List.generate(_dayShortNames.length, (index) {
                  bool isActive = _activeDayIndex == index;
                  return GestureDetector(
                    onTap: () => _onDaySelected(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: isActive ? Theme.of(context).extension<EduPortalThemeExtension>()!.primaryGradient : null,
                        color: isActive ? null : Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                        border: isActive ? null : Border.all(color: EduDesignTokens.slate200),
                        boxShadow: isActive ? Theme.of(context).extension<EduPortalThemeExtension>()!.avatarShadow : [],
                      ),
                      child: Text(
                        _dayShortNames[index],
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))),
                  ],
                ),
              ),
            ),

          Expanded(
            child: _isLoading && _weeklySchedule[_dbDayKeys[_activeDayIndex]]!.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _activeDayIndex = index);
                    _syncLiveRecords(); // Fetch overrides on swipe
                  },
                  children: _dbDayKeys.map((dayKey) => _buildDayView(dayKey)).toList(),
                ),
          ),
        ],
      ),
    );
  }
}
