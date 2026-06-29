import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutty_solar_icons/flutty_solar_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart'; 
import '../constants/theme.dart';

import '../services/auth_service.dart';
import 'login.dart'; 

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // --- SCHEDULE CLOUD SYNC STATE ---
  String? _selectedSchedule;
  final List<String> _availableSchedules = [
    'B.Tech (IT) 2024-28 [A]', 
    'B.Tech (IT) 2024-28 [B]',
    'B.Tech (CSE) 2024-28 [A]',
    'B.Tech (CSE) 2024-28 [B]'
  ];
  
  bool _isScheduleLoading = true;
  bool _isSyncingProfile = false;
  
  // --- OTA UPDATE & PACKAGE STATE ---
  bool _isCheckingForUpdate = false;
  String _appName = 'EduPortal';
  String _appVersion = '1.0.0';
  String _appPackage = '';

  final String _githubOwner = 'Byte-Craftsman-Alpha';
  final String _githubRepo = 'Flutter-AppDevelopment';
  String _apkDownloadUrl = '';
  String _releaseHtmlUrl = '';

  @override
  void initState() {
    super.initState();
    _fetchPackageInfo();
    _loadCurrentSchedule();
  }

  // --- METHODS: PACKAGE INFO & OTA UPDATES ---
  Future<void> _fetchPackageInfo() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appName = packageInfo.appName;
          _appVersion = packageInfo.version;
          _appPackage = packageInfo.packageName;
        });
      }
    } catch (e) {
      debugPrint("Error fetching package info: $e");
    }
  }

  Future<void> _manualCheckForUpdates() async {
    setState(() => _isCheckingForUpdate = true);
    
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestVersion = data['tag_name'].toString().replaceAll('v', '');
        _releaseHtmlUrl = data['html_url'];
        
        if (_isNewerVersion(latestVersion, _appVersion) && mounted) {
          _showUpdateAvailableDialog(latestVersion, data['body'] ?? 'New improvements and bug fixes.');
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('You are already on the latest version!'),
              backgroundColor: Theme.of(context).primaryColor,
            )
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to check for updates. Please try again later.'),
            backgroundColor: Colors.redAccent,
          )
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingForUpdate = false);
    }
  }

  bool _isNewerVersion(String latest, String current) {
    List<int> latestParts = latest.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    List<int> currentParts = current.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    
    for (int i = 0; i < max(latestParts.length, currentParts.length); i++) {
      int l = i < latestParts.length ? latestParts[i] : 0;
      int c = i < currentParts.length ? currentParts[i] : 0;
      if (l > c) return true;
      if (c > l) return false;
    }
    return false;
  }

  void _showUpdateAvailableDialog(String newVersion, String releaseNotes) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Available!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version $newVersion is available.'),
            const SizedBox(height: 8),
            const Text('Release Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(releaseNotes, maxLines: 5, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _launchUpdateUrl();
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUpdateUrl() async {
    if (_releaseHtmlUrl.isNotEmpty) {
      final url = Uri.parse(_releaseHtmlUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    }
  }

  // --- METHODS: CLOUD SCHEDULE SYNC ---
  Future<void> _loadCurrentSchedule() async {
    final currentGroup = await AuthService.getSubscribedSchedule();
    if (mounted) {
      setState(() {
        _selectedSchedule = currentGroup;
        _isScheduleLoading = false;
      });
    }
  }

  Future<void> _handleScheduleChange(String? newSchedule) async {
    if (newSchedule == null || newSchedule == _selectedSchedule) return;
    
    setState(() => _isSyncingProfile = true);
    
    // Save to SharedPreferences AND Sync to Cloud Database
    await AuthService.saveSubscribedSchedule(newSchedule, syncToCloud: true);
    
    setState(() {
      _selectedSchedule = newSchedule;
      _isSyncingProfile = false;
    });

    // Trigger Global Refresh across Calendar and Home Tabs instantly
    AppStateNotifier.triggerGlobalRefresh();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully subscribed to $newSchedule', style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Theme.of(context).primaryColor,
          behavior: SnackBarBehavior.floating,
        )
      );
    }
  }

  // --- METHODS: LOGOUT ---
  void _handleLogout() async {
    await AuthService.clearSession();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  // --- UI BUILDERS ---
  Widget _buildProfileRow(String label, String value, {bool isSecret = false}) {
    final textTheme = Theme.of(context).textTheme;
    final safeValue = (value == "null" || value.isEmpty) ? "Not provided" : value;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: textTheme.labelSmall?.copyWith(color: EduDesignTokens.slate400)),
                const SizedBox(height: 4),
                Text(
                  isSecret ? '•••••••• / $safeValue' : safeValue,
                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    final user = AuthService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text('My Profile', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- HEADER AVATAR ---
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: systemExt.borderNeutral,
                    backgroundImage: user?.profileUrl != null ? NetworkImage(user!.profileUrl!) : null,
                    child: user?.profileUrl == null ? const Icon(Icons.person, size: 48, color: Colors.grey) : null,
                  ),
                  const SizedBox(height: 16),
                  Text(user?.name ?? 'Student', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(user?.rollNumber ?? 'No Roll Number', style: textTheme.bodyMedium?.copyWith(color: EduDesignTokens.slate500)),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // --- PERSONAL INFORMATION CARD ---
            EduComponents.card(
              context: context,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Academic Details', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    _buildProfileRow('Email Address', user?.email ?? ''),
                    _buildProfileRow('Department', user?.department ?? ''),
                    _buildProfileRow('Semester', user?.semester ?? ''),
                    _buildProfileRow('Mobile Number', user?.mobileNo ?? ''),
                    _buildProfileRow('Father\'s Name', user?.fatherName ?? ''),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // --- CLOUD SCHEDULE SELECTOR CARD ---
            EduComponents.card(
              context: context,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Subscribed Schedule Group', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _isScheduleLoading 
                      ? const Center(child: CircularProgressIndicator())
                      : DropdownButtonFormField<String>(
                          value: _availableSchedules.contains(_selectedSchedule) ? _selectedSchedule : null,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            prefixIcon: const Icon(Icons.class_outlined),
                          ),
                          hint: const Text('Select a Class Group'),
                          items: _availableSchedules.map((String group) {
                            return DropdownMenuItem<String>(
                              value: group,
                              child: Text(group),
                            );
                          }).toList(),
                          onChanged: _isSyncingProfile ? null : _handleScheduleChange,
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // --- APP SYSTEM CARD ---
            EduComponents.card(
              context: context,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('System Configuration', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('App Version', style: textTheme.bodyMedium),
                        Text('v$_appVersion', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: EduComponents.adminSoftButton(
                        context: context,
                        onPressed: _isCheckingForUpdate ? () {} : _manualCheckForUpdates,
                        child: _isCheckingForUpdate 
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Check for Updates', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // --- LOGOUT BUTTON ---
            EduComponents.adminDangerButton(
              context: context,
              onPressed: _handleLogout,
              child: const Text('Log Out Securely', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}