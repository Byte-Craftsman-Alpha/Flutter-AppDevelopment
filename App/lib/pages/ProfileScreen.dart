import 'dart:async'; // 💡 Explicit import for TimeoutException
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
import '../services/cloud_sync_service.dart';

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
  
  Map<String, dynamic>? _liveUserData;

  String _appName = 'EduPortal';
  String _appVersion = '';
  String _appPackage = '';

  final String _githubOwner = 'Byte-Craftsman-Alpha';
  final String _githubRepo = 'Flutter-AppDevelopment';
  String _apkDownloadUrl = '';
  
  // Variables for Caching and Links
  String _releaseHtmlUrl = ''; 
  bool _isApkCached = false;
  String _cachedApkPath = '';

  bool _isCheckingForUpdate = false;
  bool _updateAvailable = false;
  String _latestVersion = '';
  String _upToDateMessage = ''; 
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
          _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
          _appPackage = packageInfo.packageName;
        });
      }
    } catch (e) {
      debugPrint("Could not fetch package info: $e");
    }
  }

  Future<void> _initializeProfileData() async {
    await CloudSyncService.bootstrapFromCloud();
    final localSub = await AuthService.getSubscribedSchedule();
    if (mounted) {
      setState(() {
        _selectedSchedule = (localSub != null && localSub.isNotEmpty) ? localSub : null;
      });
    }

    await Future.wait([
      _fetchAvailableSchedules(),
      _syncLiveProfile(silent: true),
    ]);
  }

  Future<void> _manualCheckForUpdates() async {
    setState(() {
      _isCheckingForUpdate = true;
      _upToDateMessage = '';
      _updateAvailable = false;
      _isApkCached = false;
    });

    try {
      final url = Uri.parse('https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest');
      final response = await http.get(
        url,
        headers: {"Accept": "application/vnd.github.v3+json"}
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        final String releaseName = data['name'] ?? ''; 
        final String htmlUrl = data['html_url'] ?? ''; 

        final RegExp versionRegExp = RegExp(r'v([\d\.]+)');
        final match = versionRegExp.firstMatch(releaseName);
        final String latestVersion = match != null ? match.group(1)! : '0.0.0';

        final List<dynamic> assets = data['assets'] ?? [];
        String downloadUrl = '';
        for (var asset in assets) {
          if (asset['name'].toString().endsWith('.apk')) {
            downloadUrl = asset['browser_download_url'];
            break;
          }
        }
        
        bool isNewer = _compareVersions(latestVersion, _appVersion) > 0;
        
        if (mounted) {
          if (isNewer && downloadUrl.isNotEmpty && latestVersion != '0.0.0') {
            
            // Check if this specific version is already downloaded
            final dir = await getExternalStorageDirectory();
            final expectedFilePath = '${dir!.path}/EduPortal_v$latestVersion.apk';
            final file = File(expectedFilePath);
            final bool exists = await file.exists();

            // Cleanup old APKs from previous updates to save space
            try {
              final files = dir.listSync();
              for (var f in files) {
                if (f.path.contains('EduPortal_v') && f.path.endsWith('.apk') && f.path != expectedFilePath) {
                  f.deleteSync(); 
                }
              }
            } catch (e) {
              debugPrint("Cleanup error: $e");
            }

            setState(() {
              _updateAvailable = true;
              _latestVersion = latestVersion;
              _releaseHtmlUrl = htmlUrl;
              _apkDownloadUrl = downloadUrl; 
              _isApkCached = exists;
              _cachedApkPath = expectedFilePath;
            });

          } else if (downloadUrl.isEmpty) {
            setState(() {
              _upToDateMessage = 'No APK file found in the latest release.';
            });
          } else {
            setState(() {
              _upToDateMessage = 'The app installed (v$_appVersion) is the latest version. Stay tuned!';
            });
          }
        }
      } else if (response.statusCode == 404) {
         if (mounted) {
           setState(() => _upToDateMessage = 'No releases found on GitHub yet.');
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

  int _compareVersions(String v1, String v2) {
    List<String> v1Parts = v1.split('+');
    List<String> v2Parts = v2.split('+');

    List<int> v1SemVer = v1Parts[0].split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> v2SemVer = v2Parts[0].split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < max(v1SemVer.length, v2SemVer.length); i++) {
      int p1 = i < v1SemVer.length ? v1SemVer[i] : 0;
      int p2 = i < v2SemVer.length ? v2SemVer[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }

    int b1 = v1Parts.length > 1 ? (int.tryParse(v1Parts[1]) ?? 0) : 0;
    int b2 = v2Parts.length > 1 ? (int.tryParse(v2Parts[1]) ?? 0) : 0;

    if (b1 > b2) return 1;
    if (b1 < b2) return -1;

    return 0;
  }

  // Handles Caching vs Downloading and Explicit APK Launch
  Future<void> _downloadAndInstallUpdate() async {
    // 1. If it's already downloaded, just install it!
    if (_isApkCached && _cachedApkPath.isNotEmpty) {
      _showToast("Launching Installer...", isError: false);
      final result = await OpenFile.open(
        _cachedApkPath,
        type: 'application/vnd.android.package-archive'
      );
      debugPrint("Install Status: ${result.message}");
      return;
    }

    // 2. Otherwise, start the download process
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
      final url = Uri.parse(_apkDownloadUrl);
      final request = http.Request('GET', url);
      final response = await http.Client().send(request);

      if (response.statusCode != 200) throw Exception('Server refused file transfer.');

      _totalBytes = response.contentLength ?? 0;
      
      final file = File(_cachedApkPath);
      if (await file.exists()) await file.delete();
      
      final sink = file.openWrite();

      response.stream.listen(
        (List<int> chunk) {
          sink.add(chunk);
          _downloadedBytes += chunk.length;
          if (mounted) {
            setState(() {
              if (_totalBytes > 0) _downloadProgress = _downloadedBytes / _totalBytes;
            });
          }
        },
        onDone: () async {
          await sink.flush();
          await sink.close();
          if (mounted) {
            setState(() {
              _isDownloading = false;
              _isApkCached = true; // Mark as cached now!
            });
            _showToast("Download Complete. Launching Installer...", isError: false);
          }
          // Launch the Android Installer explicitly
          final result = await OpenFile.open(
            _cachedApkPath,
            type: 'application/vnd.android.package-archive'
          );
          debugPrint("Install Status: ${result.message}");
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

  // Method to open the GitHub Release Page URL
  Future<void> _openReleaseUrl() async {
    if (_releaseHtmlUrl.isEmpty) return;
    final Uri url = Uri.parse(_releaseHtmlUrl);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _showToast("Could not open the release page.", isError: true);
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
      final url = Uri.parse('${AuthService.apiBaseUrl}/api/schedule/groups?token=$token');
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
      final url = Uri.parse('${AuthService.apiBaseUrl}/api/profile/sync?token=$token');
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final Map<String, dynamic> liveData = json.decode(response.body);
        final remoteSub = liveData['subscribed_schedule_group']?.toString();
        if (remoteSub != null && remoteSub.isNotEmpty && remoteSub != 'null') {
          await AuthService.saveSubscribedSchedule(remoteSub);
        }
        if (mounted) {
          setState(() {
            _liveUserData = liveData;
            _selectedSchedule = (remoteSub != null && remoteSub.isNotEmpty && remoteSub != 'null') ? remoteSub : _selectedSchedule;
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

  // 💡 NEW UPDATED PREFERENCE METHOD: Modals + Caching + Global Triggers
  Future<void> _updateSchedulePreference(String? newValue) async {
    if (newValue == null || newValue == _selectedSchedule) return;

    // 1. Show Confirmation Dialog
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl)),
        title: Text('Change Schedule?', style: Theme.of(context).textTheme.titleLarge),
        content: Text(
          'Do you want to switch your schedule to $newValue? This will download the new timetable and replace your current offline data.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
            ),
            child: const Text('Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isScheduleLoading = true);

    // 2. Fetch and Cache Data directly
    try {
      final user = AuthService.currentUser;
      final dept = user?.department ?? '';
      final semester = user?.semester ?? '4';
      final token = await AuthService.getAuthToken();

      final url = Uri.parse(
        '${AuthService.apiBaseUrl}/api/schedule/fetch'
        '?department=${Uri.encodeComponent(dept)}'
        '&semester=${Uri.encodeComponent(semester)}'
        '&group_name=${Uri.encodeComponent(newValue)}'
      );

      final response = await http.get(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> responseData = jsonDecode(response.body);
        
        final scheduleRecord = responseData.isNotEmpty ? responseData.first : {};
        final List<dynamic> rawClassesList = scheduleRecord['ScheduleLists'] ?? scheduleRecord['schedule_lists'] ?? [];

        // Save new schedule directly to persistent cache
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('offline_cache_schedule_$newValue', json.encode(rawClassesList));

        final cloudSaved = await CloudSyncService.updateScheduleSubscription(newValue);
        if (!cloudSaved) {
          throw Exception('Unable to save schedule subscription in cloud');
        }

        // Save preference and update UI
        await AuthService.saveSubscribedSchedule(newValue);
        if (mounted) {
          setState(() => _selectedSchedule = newValue);
        }

        // 3. Trigger global refresh for Home and Calendar tabs
        AppStateNotifier.triggerScheduleRefresh();

        _showToast("Timetable updated and synced successfully", isError: false);
      } else {
        throw Exception('Server rejected request');
      }
    } on SocketException catch (_) {
      _showToast("Failed: No internet connection. Schedule unchanged.", isError: true);
    } on TimeoutException catch (_) {
      _showToast("Failed: Connection timed out. Schedule unchanged.", isError: true);
    } catch (e) {
      debugPrint("Schedule Change Error: $e");
      _showToast("Failed to change schedule due to an unexpected error.", isError: true);
    } finally {
      if (mounted) setState(() => _isScheduleLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    await CloudSyncService.logoutDevice();
    await AuthService.clearSession();
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
            onRefresh: () async { 
              await Future.wait([
                _syncLiveProfile(silent: false),
                _fetchAvailableSchedules(),
                _manualCheckForUpdates(),
              ]);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Student Profile', style: textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),

                    // Profile Identity Card
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

                    // Schedule Dropdown Configuration
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
                                value: (_selectedSchedule != null && _availableSchedules.contains(_selectedSchedule))
                                    ? _selectedSchedule
                                    : null,
                                hint: Text('Select your academic schedule', style: TextStyle(color: EduDesignTokens.slate400, fontSize: 14)),
                                icon: EduComponents.icon(context: context, iconData: const SolarIcon(SolarIcons.AltArrowDown, weight: SolarIconWeight.outline), color: EduDesignTokens.slate400),
                                dropdownColor: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                                items: [
                                  DropdownMenuItem<String>(
                                    value: null,
                                    child: Text('Unassigned / No Schedule', style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 14)),
                                  ),
                                  ..._availableSchedules.map((String value) {
                                    return DropdownMenuItem<String>(
                                      value: value,
                                      child: Text('$value', style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 14)),
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

                    // Academic Details Container
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
                          _buildProfileRow('Enrollment No.', _extractField(['enrollment_no', 'enrollment', 'enrollment no', 'enrollmentNo'])),
                          const Divider(height: 24, thickness: 1),
                          _buildProfileRow('ABC ID.', _extractField(['apaar_id'])),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    Text('Personal Details', style: textTheme.titleMedium),
                    const SizedBox(height: 12),

                    // Academic Details Container
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
                        border: Border.all(color: systemExt.borderNeutral),
                      ),
                      child: Column(
                        children: [
                          _buildProfileRow('Father\'s Name', _extractField(['father_name', 'father'])),
                          const Divider(height: 24, thickness: 1),
                          _buildProfileRow('Mother\'s Name', _extractField(['mother_name', 'mother'])),
                          const Divider(height: 24, thickness: 1),
                          _buildProfileRow('Gender', _extractField(['gender'])),
                          const Divider(height: 24, thickness: 1),
                          _buildProfileRow('Category', _extractField(['category'])),
                          const Divider(height: 24, thickness: 1),
                          _buildProfileRow('Address', _extractField(['address'])),
                          const Divider(height: 24, thickness: 1),
                          _buildProfileRow('Aadhaar No.', _extractField(['aadhaar'])),
                        ],
                      ),
                    ),

                    const SizedBox(height: 36),

                    // App Update Prompt Section (Explicit Manual Trigger)
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
                            'An app crafted by Team Paradox, IET DDU GU',
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

  // System Update UI Section
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
                      Text(_isApkCached ? 'Update is ready to install.' : 'A new version is ready to download.', style: textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            
            if (_releaseHtmlUrl.isNotEmpty) ...[
              const SizedBox(height: 16),
              InkWell(
                onTap: _openReleaseUrl,
                borderRadius: BorderRadius.circular(EduDesignTokens.radiusM),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: systemExt.btnSoftBg, 
                    borderRadius: BorderRadius.circular(EduDesignTokens.radiusM),
                    border: Border.all(color: systemExt.borderNeutral.withOpacity(0.5))
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("View Release Details on GitHub", style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).primaryColor)),
                      Icon(Icons.open_in_new, size: 16, color: Theme.of(context).primaryColor),
                    ],
                  ),
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
                      child: Text(_isApkCached ? 'Install' : 'Download'),
                    ),
                  ),
                ],
              ),
          ] 
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
