import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutty_solar_icons/flutty_solar_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/theme.dart';
import '../services/auth_service.dart';
import '../services/attendance_db_service.dart';

import 'ChatScreen.dart';
import 'CalendarScreen.dart';
import 'VaultScreen.dart';
import 'ProfileScreen.dart';

/// Top-level background notification handler.
@pragma('vm:entry-point')
Future<void> onSilentPushNotificationReceived(Map<String, dynamic> messageData) async {
  debugPrint("Silent push received in background: $messageData");
  // Handle background data updates (e.g., ID card background changes)
}

class MyHomePage extends StatefulWidget {
  final String title;
  const MyHomePage({super.key, required this.title});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _reminders = [];
  bool _isLoadingDashboard = true;
  double _attendancePercentage = 100.0;
  List<dynamic> _todayClasses = [];
  Timer? _connectivityTimer;

  @override
  void initState() {
    super.initState();
    _startConnectivityCheck();
    _fetchDashboardContext();
    
    // 💡 Listen for global refresh triggers (e.g., from pull-to-refresh on other tabs)
    AppStateNotifier.globalRefreshNotifier.addListener(_fetchDashboardContext);
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    AppStateNotifier.globalRefreshNotifier.removeListener(_fetchDashboardContext);
    super.dispose();
  }

  // 💡 Lightweight periodic connectivity checker
  void _startConnectivityCheck() {
    _connectivityTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        final result = await InternetAddress.lookup('google.com');
        final isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
        AppStateNotifier.setNetworkStatus(isOnline);
      } on SocketException catch (_) {
        AppStateNotifier.setNetworkStatus(false);
      }
    });
  }

  Future<void> _fetchDashboardContext() async {
    setState(() => _isLoadingDashboard = true);
    try {
      await _loadLocalReminders();
      await _syncTasksFromCloud(); // Pull Tasks JSONB from backend
      
      _attendancePercentage = await AttendanceDbService.calculateAttendancePercentage();
      
      // Load today's classes logic (Simplified for dashboard)
      // You can expand this to fetch the actual cached schedule for today
      _todayClasses = []; 

    } catch (e) {
      debugPrint("Dashboard Context Error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingDashboard = false);
    }
  }

  // --- TASKS JSONB SYNC ENGINE ---
  Future<void> _loadLocalReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final String? tasksJson = prefs.getString('local_tasks');
    if (tasksJson != null) {
      _reminders = List<Map<String, dynamic>>.from(jsonDecode(tasksJson));
    }
  }

  Future<void> _saveLocalReminders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_tasks', jsonEncode(_reminders));
    _syncTasksToCloud(); // 💡 Fire and forget push to cloud
  }

  Future<void> _syncTasksToCloud() async {
    final token = await AuthService.getAuthToken();
    if (token == null || !AppStateNotifier.isOnlineNotifier.value) return;

    try {
      await http.post(
        Uri.parse('https://flutter-app-development-mu.vercel.app/api/sync/cloud-data'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'tasks': _reminders,
        }),
      );
    } catch (_) {
      // Will try again next time a task is saved
    }
  }

  Future<void> _syncTasksFromCloud() async {
    final token = await AuthService.getAuthToken();
    if (token == null || !AppStateNotifier.isOnlineNotifier.value) return;

    try {
      final res = await http.get(
        Uri.parse('https://flutter-app-development-mu.vercel.app/api/sync/cloud-data?token=$token')
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'];
        if (data != null && data['tasks_jsonb'] != null) {
          final cloudTasks = List<Map<String, dynamic>>.from(data['tasks_jsonb']);
          if (cloudTasks.isNotEmpty) {
            setState(() {
              _reminders = cloudTasks;
            });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('local_tasks', jsonEncode(_reminders));
          }
        }
      }
    } catch (_) {}
  }

  void _addTask(String task) {
    if (task.trim().isEmpty) return;
    setState(() {
      _reminders.add({'title': task, 'isCompleted': false});
    });
    _saveLocalReminders();
  }

  void _toggleTask(int index) {
    setState(() {
      _reminders[index]['isCompleted'] = !_reminders[index]['isCompleted'];
    });
    _saveLocalReminders();
  }
  
  void _deleteTask(int index) {
    setState(() {
      _reminders.removeAt(index);
    });
    _saveLocalReminders();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildDashboardTab(EduPortalThemeExtension systemExt, TextTheme textTheme) {
    return RefreshIndicator(
      onRefresh: () async {
        AppStateNotifier.triggerGlobalRefresh();
        await _fetchDashboardContext();
      },
      color: Theme.of(context).primaryColor,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.all(20),
        children: [
          // Header
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: systemExt.borderNeutral,
                backgroundImage: AuthService.currentUser?.profileUrl != null 
                    ? NetworkImage(AuthService.currentUser!.profileUrl!) 
                    : null,
                child: AuthService.currentUser?.profileUrl == null 
                    ? const Icon(Icons.person, color: Colors.grey) 
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, ${AuthService.currentUser?.name?.split(' ').first ?? 'Student'} 👋',
                      style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Ready for your classes today?',
                      style: textTheme.bodyMedium?.copyWith(color: EduDesignTokens.slate500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Attendance Quick Stat
          EduComponents.card(
            context: context,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                    ),
                    child: EduComponents.icon(context: context, iconData: SolarIcons.ChartN2, color: Theme.of(context).primaryColor, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Overall Attendance', style: textTheme.labelSmall?.copyWith(color: EduDesignTokens.slate500)),
                        const SizedBox(height: 4),
                        Text('${_attendancePercentage.toStringAsFixed(1)}%', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Tasks Section (Synced to Cloud)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('My Tasks', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                color: Theme.of(context).primaryColor,
                onPressed: () {
                  String newTask = '';
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('New Task'),
                      content: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(hintText: 'Enter task description...'),
                        onChanged: (v) => newTask = v,
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                        ElevatedButton(
                          onPressed: () {
                            _addTask(newTask);
                            Navigator.pop(context);
                          },
                          child: const Text('Add'),
                        )
                      ],
                    )
                  );
                },
              )
            ],
          ),
          
          if (_reminders.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text("No tasks yet. Enjoy your free time!", style: textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
              ),
            )
          else
            ...List.generate(_reminders.length, (index) {
              final task = _reminders[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: EduComponents.card(
                  context: context,
                  child: ListTile(
                    leading: Checkbox(
                      value: task['isCompleted'] ?? false,
                      activeColor: Theme.of(context).primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (v) => _toggleTask(index),
                    ),
                    title: Text(
                      task['title'],
                      style: TextStyle(
                        decoration: (task['isCompleted'] ?? false) ? TextDecoration.lineThrough : null,
                        color: (task['isCompleted'] ?? false) ? EduDesignTokens.slate400 : null,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: EduDesignTokens.slate400),
                      onPressed: () => _deleteTask(index),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final textTheme = Theme.of(context).textTheme;

    final List<Widget> pages = [
      _buildDashboardTab(systemExt, textTheme),
      ChatGroupPage(currentUserId: AuthService.currentUser?.rollNumber ?? ''),
      const CalendarScreen(),
      VaultPage(currentUserId: AuthService.currentUser?.rollNumber ?? ''),
      const ProfileScreen(),
    ];

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(0), 
        child: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
      ),
      body: Column(
        children: [
          // 💡 Dynamic Offline Banner
          ValueListenableBuilder<bool>(
            valueListenable: AppStateNotifier.isOnlineNotifier,
            builder: (context, isOnline, child) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: isOnline ? 0 : 36,
                width: double.infinity,
                color: systemExt.btnDangerBg,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    height: 36,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        EduComponents.icon(context: context, iconData: Icons.wifi_off, color: systemExt.btnDangerText, size: 16),
                        const SizedBox(width: 8),
                        Text('No Internet Connection - Offline Mode', style: TextStyle(color: systemExt.btnDangerText, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          
          Expanded(
            child: _isLoadingDashboard && _selectedIndex == 0
                ? const Center(child: CircularProgressIndicator())
                : IndexedStack(
                    index: _selectedIndex,
                    children: pages,
                  ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: SolarIcon(SolarIcons.HomeN2, weight: SolarIconWeight.outline),
            selectedIcon: SolarIcon(SolarIcons.HomeN2, weight: SolarIconWeight.bold),
            label: 'Home',
          ),
          NavigationDestination(
            icon: SolarIcon(SolarIcons.ChatRoundDots, weight: SolarIconWeight.outline),
            selectedIcon: SolarIcon(SolarIcons.ChatRoundDots, weight: SolarIconWeight.bold),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: SolarIcon(SolarIcons.Calendar, weight: SolarIconWeight.outline),
            selectedIcon: SolarIcon(SolarIcons.Calendar, weight: SolarIconWeight.bold),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: SolarIcon(SolarIcons.Folder, weight: SolarIconWeight.outline),
            selectedIcon: SolarIcon(SolarIcons.Folder, weight: SolarIconWeight.bold),
            label: 'Files',
          ),
          NavigationDestination(
            icon: SolarIcon(SolarIcons.User, weight: SolarIconWeight.outline),
            selectedIcon: SolarIcon(SolarIcons.User, weight: SolarIconWeight.bold),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}