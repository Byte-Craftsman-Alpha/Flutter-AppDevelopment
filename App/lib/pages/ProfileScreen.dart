import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutty_solar_icons/flutty_solar_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../constants/theme.dart';
import 'login.dart'; 

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _selectedSchedule;
  List<String> _availableSchedules = [];
  bool _isScheduleLoading = true;
  bool _isSyncingProfile = false;
  
  // 💡 Local state cache to hold freshly synced backend data without breaking AuthService structures
  Map<String, dynamic>? _liveUserData;

  // 💡 App Version State Variables
  String _appName = 'EduPortal';
  String _appVersion = '';
  String _appPackage = '';

  @override
  void initState() {
    super.initState();
    _liveUserData = AuthService.currentUser?.toMap();
    _loadAppDetails(); 
    _initializeProfileData();
  }

  Future<void> _loadAppDetails() async {
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
      debugPrint("Could not fetch package info: $e");
    }
  }

  Future<void> _initializeProfileData() async {
    // Load local schedule preference first for immediate UI rendering
    final localSub = await AuthService.getSubscribedSchedule();
    if (mounted) {
      setState(() {
        _selectedSchedule = (localSub != null && localSub.isNotEmpty) ? localSub : null;
      });
    }

    // Then securely fetch available groups and live profile from backend
    await Future.wait([
      _fetchAvailableSchedules(),
      _syncLiveProfile(silent: true),
    ]);
  }

  // 💡 SECURE ROUTE: Fetch Schedule Groups from Middleware, NOT Supabase
  Future<void> _fetchAvailableSchedules() async {
    if (!mounted) return;
    setState(() => _isScheduleLoading = true);

    try {
      final token = await AuthService.getAuthToken();
      final url = Uri.parse('https://flutter-app-development-mu.vercel.app/api/schedule/groups?token=$token');
      
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _availableSchedules = data.map((e) => e.toString()).toList();
            _availableSchedules.sort(); 
          });
        }
      }
    } on SocketException catch (_) {
      debugPrint("Offline mode: Cannot fetch schedule groups.");
    } catch (e) {
      debugPrint("Schedule fetch error: $e");
    } finally {
      if (mounted) setState(() => _isScheduleLoading = false);
    }
  }

  // 💡 SECURE ROUTE: Sync Profile data through Backend Wrapper
  Future<void> _syncLiveProfile({bool silent = false}) async {
    if (_isSyncingProfile) return;
    if (!silent && mounted) setState(() => _isSyncingProfile = true);

    try {
      final token = await AuthService.getAuthToken();
      final url = Uri.parse('https://flutter-app-development-mu.vercel.app/api/profile/sync?token=$token');
      
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> liveData = json.decode(response.body);
        if (mounted) {
          setState(() {
            _liveUserData = liveData;
          });
          if (!silent) _showToast("Profile synchronized securely.", isError: false);
        }
      } else if (!silent) {
        throw Exception("Server rejected profile sync.");
      }
    } on SocketException catch (_) {
      if (!silent) _showToast("No internet connection. Viewing offline profile.", isError: true);
    } catch (e) {
      debugPrint("Profile sync error: $e");
      if (!silent) _showToast("Failed to sync profile from server.", isError: true);
    } finally {
      if (mounted) setState(() => _isSyncingProfile = false);
    }
  }

  Future<void> _updateSchedulePreference(String? newValue) async {
    setState(() => _selectedSchedule = newValue);
    if (newValue != null) {
      await AuthService.saveSubscribedSchedule(newValue);
      _showToast("Timetable updated to $newValue", isError: false);
    } else {
      // Pass an empty string instead of using a non-existent clear method
      await AuthService.saveSubscribedSchedule('');
      _showToast("Timetable subscription removed", isError: false);
    }
  }

  Future<void> _handleLogout() async {
    // Directly clear local cache to log the user out and avoid missing method errors
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    if (!mounted) return;
    
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showToast(String message, {bool isError = true}) {
    if (!mounted) return;
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            EduComponents.icon(
              context: context, 
              iconData: isError ? EduIcons.danger : EduIcons.success, 
              color: isError ? systemExt.btnDangerText : Colors.greenAccent, 
              size: 20
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message, 
                style: TextStyle(
                  fontWeight: FontWeight.w600, 
                  fontSize: 13, 
                  color: isError ? systemExt.btnDangerText : Colors.white
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? systemExt.btnDangerBg : EduDesignTokens.slate900,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // 💡 Robust helper to extract fields from the backend JSON regardless of column case
  String _extractField(List<String> keys, {String defaultVal = "Not provided"}) {
    if (_liveUserData == null) return defaultVal;
    
    final lowerCaseMap = _liveUserData!.map((key, value) => MapEntry(key.toLowerCase().trim(), value));
    
    for (String k in keys) {
      final normalizedKey = k.toLowerCase().trim();
      if (lowerCaseMap.containsKey(normalizedKey) && lowerCaseMap[normalizedKey] != null) {
        final valStr = lowerCaseMap[normalizedKey].toString().trim();
        if (valStr.isNotEmpty && valStr != "null") return valStr;
      }
    }
    return defaultVal;
  }

  @override
  Widget build(BuildContext context) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final textTheme = Theme.of(context).textTheme;

    // Extract Display Data Safely
    final userName = _extractField(['name', 'student_name'], defaultVal: AuthService.currentUser?.name ?? "Student");
    final userRoll = _extractField(['roll_no', 'roll_number'], defaultVal: AuthService.currentUser?.rollNumber ?? "");
    final userDept = _extractField(['department', 'programme', 'branch'], defaultVal: AuthService.currentUser?.department ?? "");
    final userSem = _extractField(['semester', 'sem'], defaultVal: "4");
    
    final initialLetter = userName.isNotEmpty ? userName.substring(0, 1).toUpperCase() : "S";

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: systemExt.pageBackground),
        child: SafeArea(
          child: RefreshIndicator(
            color: Theme.of(context).primaryColor,
            onRefresh: () => _syncLiveProfile(silent: false),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Student Profile', style: textTheme.titleLarge?.copyWith(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),

                    // 💡 Profile Identity Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
                        border: Border.all(color: systemExt.borderNeutral),
                        boxShadow: systemExt.cardBaseShadow,
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 64, height: 64,
                                decoration: BoxDecoration(
                                  color: EduDesignTokens.indigo500.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.3), width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                    initialLetter, 
                                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(userName, style: textTheme.titleMedium?.copyWith(fontSize: 18), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    EduComponents.badge(
                                      backgroundColor: systemExt.btnSoftBg, 
                                      textColor: systemExt.btnSoftText, 
                                      child: Text(userRoll, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5))
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 32, thickness: 1),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isSyncingProfile ? null : () => _syncLiveProfile(silent: false),
                                  icon: _isSyncingProfile 
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    : EduComponents.icon(context: context, iconData: const SolarIcon(SolarIcons.RefreshCircle, weight: SolarIconWeight.outline), size: 18),
                                  label: const Text('Sync Data', style: TextStyle(fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Theme.of(context).primaryColor,
                                    side: BorderSide(color: systemExt.borderNeutral),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _handleLogout,
                                  icon: EduComponents.icon(context: context, iconData: const SolarIcon(SolarIcons.Logout, weight: SolarIconWeight.bold), color: systemExt.btnDangerText, size: 18),
                                  label: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: systemExt.btnDangerText,
                                    side: BorderSide(color: systemExt.btnDangerBorder),
                                    backgroundColor: systemExt.btnDangerBg,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
                                  ),
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    Text('Timetable Configuration', style: textTheme.titleMedium),
                    const SizedBox(height: 12),

                    // 💡 Schedule Dropdown Configuration
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                        border: Border.all(color: systemExt.borderNeutral),
                        boxShadow: systemExt.cardHoverShadow,
                      ),
                      child: _isScheduleLoading
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16.0),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: _selectedSchedule,
                                hint: Text('Select your academic section', style: TextStyle(color: EduDesignTokens.slate400, fontSize: 14)),
                                icon: EduComponents.icon(context: context, iconData: const SolarIcon(SolarIcons.AltArrowDown, weight: SolarIconWeight.outline), color: EduDesignTokens.slate400),
                                dropdownColor: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                                items: [
                                  const DropdownMenuItem<String>(
                                    value: null,
                                    child: Text('Unassigned / No Section', style: TextStyle(fontWeight: FontWeight.bold, color: EduDesignTokens.slate400)),
                                  ),
                                  ..._availableSchedules.map((String value) {
                                    return DropdownMenuItem<String>(
                                      value: value,
                                      child: Text('Section: $value', style: const TextStyle(fontWeight: FontWeight.w600)),
                                    );
                                  }),
                                ],
                                onChanged: _updateSchedulePreference,
                              ),
                            ),
                    ),

                    const SizedBox(height: 24),
                    Text('Academic Identity', style: textTheme.titleMedium),
                    const SizedBox(height: 12),

                    // 💡 Academic Details Container
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
                        border: Border.all(color: systemExt.borderNeutral),
                      ),
                      child: Column(
                        children: [
                          _buildProfileRow('Programme / Department', userDept),
                          const Divider(height: 24, thickness: 1),
                          _buildProfileRow('Current Semester', 'Semester $userSem'),
                          const Divider(height: 24, thickness: 1),
                          _buildProfileRow('Date of Birth', _extractField(['dob', 'date_of_birth']), isSecret: true),
                          const Divider(height: 24, thickness: 1),
                          _buildProfileRow('Email Address', _extractField(['email'])),
                          const Divider(height: 24, thickness: 1),
                          _buildProfileRow('Mobile Number', _extractField(['mobile', 'mobile_no', 'phone'])),
                          const Divider(height: 24, thickness: 1),
                          _buildProfileRow('Enrollment No.', _extractField(['enrollment_no', 'enrollment'])),
                        ],
                      ),
                    ),

                    const SizedBox(height: 36),
                    
                    // App Information Footer
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: systemExt.btnSoftBg, shape: BoxShape.circle),
                            child: EduComponents.icon(context: context, iconData: const SolarIcon(SolarIcons.Code, weight: SolarIconWeight.outline), size: 24, color: EduDesignTokens.slate400),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '$_appName v$_appVersion',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: EduDesignTokens.slate500),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Secure Academic Middleware System',
                            style: TextStyle(fontSize: 11, color: EduDesignTokens.slate400.withOpacity(0.8)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _appPackage,
                            style: TextStyle(fontSize: 10, color: EduDesignTokens.slate400.withOpacity(0.5)),
                          ),
                          const SizedBox(height: 36),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileRow(String label, String value, {bool isSecret = false}) {
    final textTheme = Theme.of(context).textTheme;
    final safeValue = (value == "null" || value.isEmpty) ? "Not provided" : value;
    
    return Row(
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
    );
  }
}