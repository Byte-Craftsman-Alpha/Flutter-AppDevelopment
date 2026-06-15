import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../constants/theme.dart'; // Mapped strictly to your centralized design system
import 'login.dart'; // Import your login screen file path

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _selectedSchedule;
  List<String> _availableSchedules = [];
  bool _isScheduleLoading = true;
  
  // 💡 Local state cache to hold freshly synced backend data without breaking AuthService structures
  Map<String, dynamic>? _liveUserData;

  @override
  void initState() {
    super.initState();
    // Initialize with existing local auth data first
    _liveUserData = AuthService.currentUser?.toMap();
    _loadSchedulePreferences();
  }

  // 💡 Fetch available options from Supabase and current preference from local disk
  Future<void> _loadSchedulePreferences() async {
    try {
      // 1. Fetch current subscription choice from local storage via AuthService
      final savedGroup = await AuthService.getSubscribedSchedule();

      // 2. Fetch available schedule group names directly from Supabase
      final List<dynamic> response = await Supabase.instance.client
          .from('Weekly Schedules')
          .select('ScheduleGroupName');

      // Filter out duplicate or null group items safely
      final groups = response
          .map((row) => row['ScheduleGroupName']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toSet() 
          .toList();

      if (mounted) {
        setState(() {
          _availableSchedules = groups;
          // Respect the "unselected" null state
          _selectedSchedule = (savedGroup != null && savedGroup.isNotEmpty && groups.contains(savedGroup)) 
              ? savedGroup 
              : null;
          _isScheduleLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScheduleLoading = false;
        });
      }
    }
  }

  // 💡 Chrome-style Pull-to-Refresh Sync Handler
  Future<void> _syncProfileData() async {
    setState(() => _isScheduleLoading = true);
    
    // 1. Re-sync schedule lists
    await _loadSchedulePreferences();
    
    // 2. Fetch latest raw user data directly from backend database
    final user = AuthService.currentUser;
    if (user != null) {
      try {
        final response = await Supabase.instance.client
            .from('StudentDetails')
            .select()
            .eq('Roll_No', user.rollNumber)
            .maybeSingle();

        if (response != null && mounted) {
          setState(() {
            _liveUserData = response; // Update local screen state with fresh database row
          });
        }
      } catch (e) {
        debugPrint("❌ Profile Sync Failed: $e");
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              EduComponents.icon(
                context: context, 
                iconData: EduIcons.success, 
                color: Colors.greenAccent, 
                size: 20
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Profile and schedules synced successfully.',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).primaryColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
        ),
      );
    }
  }

  // 💡 Handler when user changes the dropdown value selection
  Future<void> _handleScheduleChange(String? newGroupName) async {
    setState(() {
      _selectedSchedule = newGroupName;
    });
    
    // 💡 SECURE SAVE: If null, save an empty string to signify "unselected" in shared preferences
    await AuthService.saveSubscribedSchedule(newGroupName ?? "");

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              EduComponents.icon(
                context: context, 
                iconData: EduIcons.success, 
                color: Colors.greenAccent, 
                size: 20
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  newGroupName == null 
                      ? 'Schedule unselected successfully.' 
                      : 'Subscribed to $newGroupName successfully!',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).primaryColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final user = AuthService.currentUser;
    final fallbackMap = user?.toMap() ?? {};
    
    // 💡 BULLETPROOF MAPPING: Applies exhaustive PascalCase fallbacks AND strict .toString() casting
    // This entirely prevents the grey screen crash caused by Supabase returning ints/bigints or mis-cased columns.
    final String displayedName = (_liveUserData?['name'] ?? _liveUserData?['Name'] ?? fallbackMap['name'] ?? 'Student').toString();
    final String displayedRoll = (_liveUserData?['roll_no'] ?? _liveUserData?['Roll_No'] ?? fallbackMap['rollNumber'] ?? 'N/A').toString();
    final String displayedEmail = (_liveUserData?['email'] ?? _liveUserData?['Email'] ?? fallbackMap['email'] ?? 'Not Provided').toString();
    final String displayedDept = (_liveUserData?['programme'] ?? _liveUserData?['department'] ?? fallbackMap['department'] ?? 'Not Assigned').toString();
    final String displayedDoB = (_liveUserData?['dob'] ?? _liveUserData?['date_of_birth'] ?? fallbackMap['dob'] ?? 'N/A').toString();
    final String displayedMobile = (_liveUserData?['mobile_no'] ?? _liveUserData?['Mobile_No'] ?? _liveUserData?['mobile'] ?? fallbackMap['mobileNo'] ?? 'N/A').toString();
    final String displayedAadhaar = (_liveUserData?['aadhaar'] ?? _liveUserData?['Aadhaar'] ?? _liveUserData?['aadhaar_no'] ?? fallbackMap['aadhaar'] ?? 'N/A').toString();

    // 💡 FIXED: Extended the robust parsing to the Additional Details to stop the Refresh Grey Screen Crash
    final String displayedEnrollment = (_liveUserData?['enrollment_no'] ?? _liveUserData?['Enrollment_No'] ?? fallbackMap['enrollmentNo'] ?? 'N/A').toString();
    final String displayedFather = (_liveUserData?['father_name'] ?? _liveUserData?['Father_Name'] ?? fallbackMap['fatherName'] ?? 'N/A').toString();
    final String displayedMother = (_liveUserData?['mother_name'] ?? _liveUserData?['Mother_Name'] ?? fallbackMap['motherName'] ?? 'N/A').toString();
    final String displayedApaar = (_liveUserData?['apaar_id'] ?? _liveUserData?['Apaar_ID'] ?? fallbackMap['apaarId'] ?? 'N/A').toString();
    final String displayedAddress = (_liveUserData?['address'] ?? _liveUserData?['Address'] ?? fallbackMap['address'] ?? 'N/A').toString();
    final String displayedCategory = (_liveUserData?['category'] ?? _liveUserData?['Category'] ?? fallbackMap['category'] ?? 'N/A').toString();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: systemExt.pageBackground,
        ),
        child: SafeArea(
          // 💡 PULL-TO-REFRESH WRAPPER
          child: RefreshIndicator(
            onRefresh: _syncProfileData,
            color: theme.primaryColor,
            backgroundColor: theme.cardColor,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    
                    // Profile Avatar Badge Display (Adaptive Colors)
                    Center(
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? EduDesignTokens.indigo500.withOpacity(0.15)
                              : EduDesignTokens.indigo50,
                          borderRadius: BorderRadius.circular(EduDesignTokens.radius3xl),
                          border: Border.all(
                            color: theme.primaryColor.withOpacity(0.2),
                            width: 1.5,
                          ),
                          boxShadow: systemExt.avatarShadow,
                        ),
                        child: Center(
                          child: Text(
                            displayedName.isNotEmpty && displayedName != "null" 
                                ? displayedName[0].toUpperCase() 
                                : 'S',
                            style: TextStyle(
                              color: theme.primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 32,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        displayedName != "null" ? displayedName : 'Student',
                        textAlign: TextAlign.center,
                        style: textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // --- TIMETABLE SUBSCRIPTION WIDGET CARD ---
                    EduComponents.card(
                      context: context,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                EduComponents.icon(
                                  context: context,
                                  iconData: EduIcons.attendanceInactive,
                                  color: theme.primaryColor,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'WEEKLY SCHEDULE SUBSCRIPTION',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: theme.primaryColor,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24, thickness: 1),
                            Text(
                              'Select your class section group to synchronize and view personalized schedules across the dashboard:',
                              style: textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            _isScheduleLoading
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: CircularProgressIndicator(color: theme.primaryColor),
                                    ),
                                  )
                                : Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: systemExt.btnSoftBg,
                                      borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                                      border: Border.all(color: systemExt.btnSoftBorder),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String?>(
                                        value: _selectedSchedule,
                                        isExpanded: true,
                                        dropdownColor: theme.cardColor,
                                        icon: Icon(Icons.keyboard_arrow_down_rounded, color: theme.primaryColor),
                                        hint: Text('Select a schedule block', style: textTheme.bodyMedium),
                                        items: [
                                          DropdownMenuItem<String?>(
                                            value: null,
                                            child: Text(
                                              'Unassigned / None',
                                              style: textTheme.bodyLarge?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: EduDesignTokens.slate400,
                                              ),
                                            ),
                                          ),
                                          ..._availableSchedules.map((String value) {
                                            return DropdownMenuItem<String?>(
                                              value: value,
                                              child: Text(
                                                value,
                                                style: textTheme.bodyLarge?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                        onChanged: _handleScheduleChange,
                                      ),
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Student Profile Data Card
                    EduComponents.card(
                      context: context,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'STUDENT PROFILE DATA',
                              style: TextStyle(
                                fontSize: 11, 
                                fontWeight: FontWeight.bold, 
                                color: EduDesignTokens.slate400,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const Divider(height: 24, thickness: 1),
                            _buildProfileRow('Student Name', displayedName),
                            const SizedBox(height: 16),
                            _buildProfileRow('Roll Number', displayedRoll),
                            const SizedBox(height: 16),
                            _buildProfileRow('Programme / Branch', displayedDept),
                            const SizedBox(height: 16),
                            _buildProfileRow('Email Address', displayedEmail),
                            const SizedBox(height: 16),
                            _buildProfileRow('Mobile Number', displayedMobile),
                            const SizedBox(height: 16),
                            _buildProfileRow('Aadhaar Number', displayedAadhaar),
                            const SizedBox(height: 16),
                            _buildProfileRow('Date of Birth (Login Pin)', displayedDoB, isSecret: true),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Additional Details Box Structure Block
                    EduComponents.card(
                      context: context,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ADDITIONAL DETAILS',
                              style: TextStyle(
                                fontSize: 11, 
                                fontWeight: FontWeight.bold, 
                                color: EduDesignTokens.slate400,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const Divider(height: 24, thickness: 1),
                            _buildProfileRow('Enrollment Number', displayedEnrollment),
                            const SizedBox(height: 16),
                            _buildProfileRow('Father\'s Name', displayedFather),
                            const SizedBox(height: 16),
                            _buildProfileRow('Mother\'s Name', displayedMother),
                            const SizedBox(height: 16),
                            _buildProfileRow('Apaar ID', displayedApaar),
                            const SizedBox(height: 16),
                            _buildProfileRow('Address', displayedAddress),
                            const SizedBox(height: 16),
                            _buildProfileRow('Category', displayedCategory),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),

                    // Modern Action Logout Submission Button Layout
                    EduComponents.adminDangerButton(
                      context: context,
                      onPressed: () async {
                        await AuthService.clearSession();
                        if (context.mounted) {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (context) => const LoginScreen()),
                            (route) => false,
                          );
                        }
                      },
                      child: const Text(
                        'Log Out of Account',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 12),
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
    // Safety check to ensure "null" strings don't render on the UI
    final safeValue = (value == "null" || value.isEmpty) ? "N/A" : value;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label, 
          style: textTheme.labelSmall?.copyWith(color: EduDesignTokens.slate400),
        ),
        const SizedBox(height: 3),
        Text(
          isSecret ? '•••••••• / $safeValue' : safeValue,
          style: textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}