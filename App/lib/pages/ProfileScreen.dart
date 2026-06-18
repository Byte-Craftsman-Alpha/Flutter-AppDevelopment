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
  
  // 💡 Local state cache to hold freshly synced backend data
  Map<String, dynamic>? _liveUserData;

  // 💡 App Version State Variables
  String _appName = 'EduPortal';
  String _appVersion = '';
  String _appPackage = '';

  // 💡 GitHub Repository Info (Replace these with your actual info)
  final String _githubOwner = 'Byte-Craftsman-Alpha';
  final String _githubRepo = 'Flutter-AppDevelopment';
  String _apkDownloadUrl = '';

  // 💡 Update Control Variables
  bool _isCheckingForUpdate = false;
  bool _updateAvailable = false;
  String _latestVersion = '';
  String _releaseNotes = '';
  String _upToDateMessage = ''; // Holds the "already latest" message
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;

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
    final localSub = await AuthService.getSubscribedSchedule();
    if (mounted) {
      setState(() {
        _selectedSchedule = (localSub != null && localSub.isNotEmpty) ? localSub : null;
      });
    }

    // Securely fetch available groups and live profile
    await Future.wait([
      _fetchAvailableSchedules(),
      _syncLiveProfile(silent: true),
    ]);
  }

  // 💡 MANUAL ROUTE: Check for APK updates directly from GitHub
  Future<void> _manualCheckForUpdates() async {
    setState(() {
      _isCheckingForUpdate = true;
      _upToDateMessage = '';
      _updateAvailable = false;
    });

    try {
      // Direct call to GitHub API
      final url = Uri.parse('https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest');
      final response = await http.get(
        url,
        headers: {"Accept": "application/vnd.github.v3+json"}
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final String tagName = data['tag_name'] ?? 'v1.0.0';
        final String latestVersion = tagName.replaceAll('v', '').trim();
        final String releaseNotes = data['body'] ?? 'No release notes provided.';

        // Find the APK asset in the release payload
        final List<dynamic> assets = data['assets'] ?? [];
        String downloadUrl = '';
        for (var asset in assets) {
          if (asset['name'].toString().endsWith('.apk')) {
            downloadUrl = asset['browser_download_url'];
            break;
          }
        }

        PackageInfo packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version; // e.g., "1.0.0"
        
        // Compare versions locally
        bool isNewer = _compareVersions(latestVersion, currentVersion) > 0;
        
        if (mounted) {
          if (isNewer && downloadUrl.isNotEmpty) {
            setState(() {
              _updateAvailable = true;
              _latestVersion = latestVersion;
              _releaseNotes = releaseNotes;
              _apkDownloadUrl = downloadUrl; // Store the direct CDN link
            });
          } else if (downloadUrl.isEmpty) {
            setState(() {
              _upToDateMessage = 'No APK file found in the latest release.';
            });
          } else {
            setState(() {
              _upToDateMessage = 'The app installed (v$_appVersion) is the latest version. No newer versions are released yet, stay tuned!';
            });
          }
        }
      } else if (response.statusCode == 404) {
         if (mounted) {
           setState(() {
              _upToDateMessage = 'No releases found on GitHub yet.';
           });
         }
      } else {
        throw Exception("GitHub API Error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("App update check failed: $e");
      if (mounted) {
        _showToast("Failed to connect to GitHub update server.", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingForUpdate = false);
      }
    }
  }

  // Helper to securely compare semantic versions (e.g., 1.0.5 vs 1.0.4)
  int _compareVersions(String v1, String v2) {
    List<int> v1Parts = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> v2Parts = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < max(v1Parts.length, v2Parts.length); i++) {
      int p1 = i < v1Parts.length ? v1Parts[i] : 0;
      int p2 = i < v2Parts.length ? v2Parts[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }
    return 0;
  }

  // 💡 APP UPDATER: Persistent Download & Install
  Future<void> _downloadAndInstallUpdate() async {
    if (_apkDownloadUrl.isEmpty) {
       _showToast("Download URL not found.", isError: true);
       return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadedBytes = 0;
      _totalBytes = 0;
    });

    try {
      // Download directly from GitHub's CDN using the extracted asset URL
      final url = Uri.parse(_apkDownloadUrl);
      final request = http.Request('GET', url);
      // GitHub redirects asset links to an AWS S3 bucket. http.Client handles this natively.
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        throw Exception('Server refused file transfer.');
      }

      _totalBytes = response.contentLength ?? 0;
      
      // 💡 Persist to External Storage: Prevents deletion on restart.
      // Saving as 'EduPortal_Update.apk' guarantees that every new download 
      // overwrites the old one, preventing storage clutter!
      final dir = await getExternalStorageDirectory();
      final filePath = '${dir!.path}/EduPortal_Update.apk';
      final file = File(filePath);
      
      // Clear incomplete fragments if they exist
      if (await file.exists()) {
        await file.delete();
      }
      
      final sink = file.openWrite();

      response.stream.listen(
        (List<int> chunk) {
          sink.add(chunk);
          _downloadedBytes += chunk.length;
          if (mounted) {
            setState(() {
              if (_totalBytes > 0) {
                _downloadProgress = _downloadedBytes / _totalBytes;
              }
            });
          }
        },
        onDone: () async {
          await sink.flush();
          await sink.close();
          if (mounted) {
            setState(() {
              _isDownloading = false;
              _updateAvailable = false; 
            });
            _showToast("Download Complete. Launching Installer...", isError: false);
          }
          // Launch the Android Installer
          await OpenFile.open(filePath);
        },
        onError: (e) async {
          await sink.close();
          if (mounted) {
            setState(() => _isDownloading = false);
            _showToast("Update download was interrupted.", isError: true);
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint("Download error: $e");
      if (mounted) {
        setState(() => _isDownloading = false);
        _showToast("Failed to download update.", isError: true);
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

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
    } catch (e) {
      debugPrint("Schedule fetch error: $e");
    } finally {
      if (mounted) setState(() => _isScheduleLoading = false);
    }
  }

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
          setState(() => _liveUserData = liveData);
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
      await AuthService.saveSubscribedSchedule('');
      _showToast("Timetable subscription removed", isError: false);
    }
  }

  Future<void> _handleLogout() async {
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
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isError ? systemExt.btnDangerText : Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? systemExt.btnDangerBg : EduDesignTokens.slate900,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

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
                    Text('Student Profile', style: textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.bold)),
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
                                  DropdownMenuItem<String>(
                                    value: null,
                                    child: Text('Unassigned / No Section', style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 14)),
                                  ),
                                  ..._availableSchedules.map((String value) {
                                    return DropdownMenuItem<String>(
                                      value: value,
                                      child: Text('Section: $value', style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 14)),
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
                          _buildProfileRow('Enrollment No.', _extractField(['enrollment_no', 'enrollment', 'enrollmentno', 'enrollmentNo'])),
                        ],
                      ),
                    ),

                    const SizedBox(height: 36),

                    // 💡 App Update Prompt Section (Explicit Manual Trigger)
                    Text('System Updates', style: textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _buildSystemUpdateSection(),

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

  // 💡 System Update UI Section
  Widget _buildSystemUpdateSection() {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
        border: Border.all(
          color: _updateAvailable ? systemExt.borderFocus : systemExt.borderNeutral, 
          width: _updateAvailable ? 1.5 : 1.0
        ),
        boxShadow: _updateAvailable ? [
          BoxShadow(
            color: systemExt.borderFocus.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ] : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // If an update IS available
          if (_updateAvailable) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(color: EduDesignTokens.indigo50, shape: BoxShape.circle),
                  child: EduComponents.icon(context: context, iconData: Icons.system_update_rounded, color: EduDesignTokens.indigo600, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Update Available (v$_latestVersion)', style: textTheme.titleMedium?.copyWith(color: EduDesignTokens.indigo600)),
                      Text('A new version is ready to install.', style: textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            if (_releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                decoration: BoxDecoration(color: systemExt.btnSoftBg, borderRadius: BorderRadius.circular(EduDesignTokens.radiusM)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Release Notes", style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(_releaseNotes, style: textTheme.bodyMedium?.copyWith(fontSize: 13)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (_isDownloading)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Downloading...', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: EduDesignTokens.indigo600)),
                      Text('${_formatBytes(_downloadedBytes)} / ${_formatBytes(_totalBytes)}', style: textTheme.labelSmall),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(EduDesignTokens.radiusFull),
                    child: LinearProgressIndicator(
                      value: _totalBytes > 0 ? _downloadProgress : null,
                      minHeight: 8,
                      backgroundColor: systemExt.btnSoftBg,
                      valueColor: AlwaysStoppedAnimation<Color>(systemExt.borderFocus),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(child: Text('${(_downloadProgress * 100).toStringAsFixed(1)}%', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold))),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: EduComponents.adminSoftButton(
                      context: context,
                      onPressed: () => setState(() => _updateAvailable = false),
                      child: const Text('Later'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: EduComponents.primaryGradientButton(
                      context: context,
                      onPressed: _downloadAndInstallUpdate,
                      child: const Text('Update Now'),
                    ),
                  ),
                ],
              ),
          ] 
          // Default state or "Checking" State
          else ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: systemExt.btnSoftBg, shape: BoxShape.circle),
                  child: EduComponents.icon(context: context, iconData: const SolarIcon(SolarIcons.SmartphoneUpdate, weight: SolarIconWeight.outline), color: EduDesignTokens.slate500, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Check for Updates', style: textTheme.titleMedium),
                      Text('Current Version: v$_appVersion', style: textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            
            if (_upToDateMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: EduDesignTokens.emerald50,
                  borderRadius: BorderRadius.circular(EduDesignTokens.radiusM),
                  border: Border.all(color: EduDesignTokens.emerald200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: EduDesignTokens.emerald600, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_upToDateMessage, style: textTheme.bodyMedium?.copyWith(color: EduDesignTokens.emerald700, fontSize: 13, height: 1.3)),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),
            EduComponents.adminSoftButton(
              context: context,
              onPressed: _isCheckingForUpdate ? () {} : _manualCheckForUpdates,
              child: _isCheckingForUpdate 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Check for Updates', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ],
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