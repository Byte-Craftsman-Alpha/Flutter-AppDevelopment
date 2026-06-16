import 'dart:convert';
import 'dart:async'; // Added for TimeoutException handling
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutty_solar_icons/flutty_solar_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../constants/theme.dart';
import '../services/auth_service.dart';
import '../services/crypto_service.dart';

import 'ChatScreen.dart';
import 'CalendarScreen.dart';
import 'VaultScreen.dart';
import 'ProfileScreen.dart';

class MyHomePage extends StatefulWidget {
  final String title;
  const MyHomePage({super.key, required this.title});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _hasSyncError = false; // 💡 Track network failures gracefully
  String _greeting = 'Welcome';

  List<Map<String, dynamic>> _todayClasses = [];
  List<Map<String, dynamic>> _todayEvents = [];
  List<Map<String, dynamic>> _recentVaultItems = [];

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
    _determineGreeting();
    _fetchDashboardContext();
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

  // 💡 Centralized Error SnackBar to prevent dead interactions
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
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

  Future<void> _fetchDashboardContext() async {
    setState(() {
      _isLoading = true;
      _hasSyncError = false;
    });

    try {
      final token = await AuthService.getAuthToken();
      final groupName = await AuthService.getSubscribedSchedule() ?? '';

      // 1. Fetch Latest 4 Vault Documents (With 15s Timeout)
      final vaultUrl = Uri.parse(
        'https://flutter-app-development-mu.vercel.app/api/vault/records?token=$token',
      );
      final vaultRes = await http.get(vaultUrl).timeout(const Duration(seconds: 15));

      if (vaultRes.statusCode == 200) {
        final List<dynamic> records = json.decode(vaultRes.body);
        final List<Map<String, dynamic>> typedRecords = records.cast<Map<String, dynamic>>();

        typedRecords.sort((a, b) {
          final dateA = DateTime.tryParse(a['created_at'].toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final dateB = DateTime.tryParse(b['created_at'].toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return dateB.compareTo(dateA);
        });

        _recentVaultItems = typedRecords.take(4).toList();
      } else {
        throw Exception('Vault API rejected payload');
      }

      // 2. Fetch Today's Schedule (From Cache)
      if (groupName.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final String? cachedScheduleStr = prefs.getString('offline_cache_schedule_$groupName');

        if (cachedScheduleStr != null) {
          final List<dynamic> rawClassesList = json.decode(cachedScheduleStr);

          final currentDayString = DateFormat('EEEE').format(DateTime.now()).toLowerCase();
          final now = DateTime.now();
          final currentMinutes = now.hour * 60 + now.minute;

          _todayClasses = rawClassesList
              .map((e) => Map<String, dynamic>.from(e))
              .where((c) {
                if ((c['day']?.toString().toLowerCase().trim() ?? '') != currentDayString) {
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
            (a, b) => (a['time'] ?? '').toString().compareTo((b['time'] ?? '').toString()),
          );
        }
      }

      // 3. Fetch Today's Events (From Cache)
      final prefs = await SharedPreferences.getInstance();
      final String? cachedEventsStr = prefs.getString('offline_cache_monthly_calendar');

      if (cachedEventsStr != null) {
        final List<dynamic> eventsData = json.decode(cachedEventsStr);
        final todayString =
            "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";

        _todayEvents = eventsData
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) {
              final eventDate = e['Date']?.toString() ?? e['date']?.toString() ?? '';
              return eventDate == todayString;
            })
            .toList();
      }
    } catch (e) {
      debugPrint("❌ Dashboard Sync Error: $e");
      if (mounted) {
        setState(() => _hasSyncError = true);
        _showErrorSnackBar('Connection failed. Please check your internet and try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 💡 Open browser logic natively with graceful exception handling
  Future<void> _launchExternalUrl(String urlString) async {
    try {
      final Uri url = Uri.parse(urlString);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Unable to open the external website. Please try again.');
      }
    }
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
                                    _showErrorSnackBar('Invalid or Foreign QR Code Detected!');
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
  Future<Map<String, List<Map<String, dynamic>>>> _fetchStaffFromBackend() async {
    try {
      final token = await AuthService.getAuthToken() ?? '';
      final url = Uri.parse(
        'https://flutter-app-development-mu.vercel.app/api/directory/staff?token=$token',
      );
      // 💡 Added strict timeout to prevent infinite modal hanging
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
                      color: isDark ? EduDesignTokens.indigo50.withOpacity(0.15) : EduDesignTokens.indigo50.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: SolarIcon(
                      SolarIcons.UsersGroupRounded,
                      color: theme.primaryColor,
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
                    // 💡 Gracefully handle the error UI to match existing styles
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
        'https://flutter-app-development-mu.vercel.app/api/library/books?token=$token',
      );
      // 💡 Added strict timeout to prevent infinite modal hanging
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      }
      throw Exception('Server rejected payload');
    } catch (e) {
      debugPrint('Library Sync Error: $e');
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
                      color: isDark ? EduDesignTokens.emerald50.withOpacity(0.15) : EduDesignTokens.emerald50.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      color: EduDesignTokens.emerald600,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text('E-Library Portal', style: theme.textTheme.titleLarge),
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
                    // 💡 Gracefully handle the error UI to match existing styles
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text(
                          "Unable to connect to the library. Please check your internet connection.",
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
                      child: Text("Library is currently empty."),
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

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: systemExt.primaryGradient,
        borderRadius: BorderRadius.circular(EduDesignTokens.radius3xl),
        boxShadow: systemExt.authCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_greeting,',
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
                  ],
                ),
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                  border: Border.all(color: Colors.white.withOpacity(0.4)),
                ),
                child: const Center(
                  child: SolarIcon(
                    SolarIcons.User,
                    weight: SolarIconWeight.bold,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
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
          'Library',
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
          () => _launchExternalUrl('https://erp.ddugu.ac.in/student_login.aspx'),
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

  Widget _buildTodaySchedule() {
    final theme = Theme.of(context);
    final systemExt = theme.extension<EduPortalThemeExtension>()!;

    if (_todayClasses.isEmpty && _todayEvents.isEmpty) {
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
                // 💡 Conditionally show error message if the fetch failed securely
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

    // Render Events First (Holidays/Special Events)
    for (var event in _todayEvents) {
      scheduleWidgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: EduComponents.card(
            context: context,
            child: Container(
              decoration: BoxDecoration(
                color: systemExt.btnDangerBg,
                borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
                border: Border.all(
                  color: systemExt.btnDangerBorder,
                  width: 1.5,
                ),
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
        ),
      );
    }

    // Render Remaining / Active Classes
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

      scheduleWidgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: EduComponents.card(
            context: context,
            child: Container(
              decoration: BoxDecoration(
                color: isOngoing
                    ? EduDesignTokens.indigo50.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
                border: isOngoing
                    ? Border.all(color: systemExt.borderFocus, width: 2.0)
                    : null,
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
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
                        Text(
                          subject,
                          style: theme.textTheme.bodyLarge?.copyWith(
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
                // 💡 Conditionally show error message if the fetch failed securely
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
                '$extension · $sizeKb KB',
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
      onRefresh: _fetchDashboardContext,
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

                  // 3. Today's Academic Schedule Pipeline
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

                  // 5. Cloud Storage Synchronization Stream
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Recent Uploads",
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SolarIcon(
                        SolarIcons.CloudCheck,
                        color: Theme.of(context).primaryColor,
                        size: 20,
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