import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutty_solar_icons/flutty_solar_icons.dart';
import '../constants/theme.dart'; // Mapped strictly to your centralized design system
import '../models/user.dart';
import '../services/auth_service.dart';
import 'home.dart'; // Ensure correct import to your dashboard page class

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _rollController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isPasswordObscured = true;
  bool _isLoading = false; // Tracks active query status to render loading indicator

  @override
  void dispose() {
    _rollController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    // 💡 Run form validation check OUTSIDE the try-catch block.
    // This prevents layout/theme-rendering crashes from getting caught and reported as server connection errors.
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true; // Trigger visual spinner feedback
    });

    final rollNumber = _rollController.text.trim();
    final enteredPassword = _passwordController.text.trim(); // Acts as Date of Birth

    try {
      // 💡 Secure 3-Tier Architecture Call: Routes credentials directly to your live Vercel Gateway
      final url = Uri.parse('https://flutter-app-development-mu.vercel.app/api/auth/login');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'roll_number': rollNumber,
          'password': enteredPassword,
        }),
      );

      // 💡 FIXED: Check status code FIRST before attempting to decode response.body as JSON.
      // This prevents a FormatException crash when the server returns plain text / HTML (like "Internal Server Error") on failure.
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        final Map<String, dynamic> studentData = responseData['user'] ?? {};
        final String jwtToken = responseData['access_token'] ?? '';

        // 💡 Explicit compilation protection: Mapping response keys into clear properties blocks.
        // This ensures your parsing sequence perfectly survives R8/ProGuard code shrinking minification!
        final user = UserModel(
          id: studentData['id']?.toString() ?? '',
          name: studentData['name']?.toString() ?? '',
          rollNumber: studentData['roll_number']?.toString() ?? '',
          email: studentData['email']?.toString() ?? '',
          department: studentData['department']?.toString() ?? '',
          dob: studentData['dob']?.toString() ?? '',
          mobileNo: studentData['Mobile_No']?.toString() ?? studentData['mobile_no']?.toString() ?? '',
          aadhaar: studentData['Aadhaar']?.toString() ?? studentData['aadhaar']?.toString() ?? '',
          enrollmentNo: studentData['enrollment_no']?.toString() ?? studentData['Enrollment_No']?.toString() ?? '',
          apaarId: studentData['apaar_id']?.toString() ?? studentData['Apaar_ID']?.toString() ?? '',
          address: studentData['address']?.toString() ?? '',
          category: studentData['category']?.toString() ?? '',
          gender: studentData['gender']?.toString() ?? '',
          fatherName: studentData['father_name']?.toString() ?? studentData['Father_Name']?.toString() ?? '',
          motherName: studentData['mother_name']?.toString() ?? studentData['Mother_Name']?.toString() ?? '',
          semester: studentData['semester']?.toString() ?? '4',
        );

        // 💡 Save user session persistently alongside the secure server-signed JWT token
        await AuthService.saveSession(user, token: jwtToken);

        // Route user into main Dashboard and clear history stack
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const MyHomePage(title: 'EduPortal'),
            ),
          );
        }
      } else {
        // 💡 FIXED: Safely handle non-200 responses without crashing on plain-text errors
        String errorMessage = 'Server Error (${response.statusCode})';
        try {
          final Map<String, dynamic> responseData = jsonDecode(response.body);
          errorMessage = responseData['detail']?.toString() ?? 
                         responseData['message']?.toString() ?? 
                         errorMessage;
        } catch (_) {
          // If response is plain text like "Internal Server Error", extract it safely here
          if (response.body.isNotEmpty) {
            errorMessage = response.body.trim();
          }
        }
        _showErrorSnackBar(errorMessage);
      }
    } catch (e) {
      _showErrorSnackBar('Gateway Connection Error: Unable to communicate with authentication server.\nDetails: $e');
      debugPrint('❌ Network Exceptions Details: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false; // Turn spinner off
        });
      }
    }
  }

  void _showErrorSnackBar(String message, {bool isLongDuration = false}) {
    if (!mounted) return;
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            EduComponents.icon(
              context: context, 
              iconData: EduIcons.danger, 
              color: systemExt.btnDangerText, 
              size: 20
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message, 
                style: TextStyle(fontWeight: FontWeight.bold, color: systemExt.btnDangerText, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: systemExt.btnDangerBg,
        duration: Duration(seconds: isLongDuration ? 6 : 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
          side: BorderSide(color: systemExt.btnDangerBorder),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: systemExt.pageBackground,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand Identity Animated Logo placeholder 
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          gradient: systemExt.primaryGradient,
                          borderRadius: BorderRadius.circular(EduDesignTokens.radius3xl),
                          boxShadow: systemExt.avatarShadow,
                        ),
                        child: EduComponents.icon(
                          context: context,
                          iconData: const SolarIcon(SolarIcons.Widget, weight: SolarIconWeight.bold),
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                    Text(
                      'Welcome Back',
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sign in to your EduPortal account',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 36),

                    // Premium auth credentials card wrapper 
                    EduComponents.card(
                      context: context,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _rollController,
                              keyboardType: TextInputType.number, // Prompt numeric keypad for numeric roll numbers
                              enabled: !_isLoading, // Block typing while querying
                              style: textTheme.bodyLarge?.copyWith(fontSize: 14),
                              decoration: InputDecoration(
                                labelText: 'Roll Number',
                                hintText: 'e.g., 2514670010038',
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: EduComponents.icon(
                                    context: context,
                                    iconData: const SolarIcon(SolarIcons.User, weight: SolarIconWeight.outline),
                                    size: 20,
                                    color: EduDesignTokens.slate400,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your roll number';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _isPasswordObscured,
                              enabled: !_isLoading,
                              keyboardType: TextInputType.text,
                              style: textTheme.bodyLarge?.copyWith(fontSize: 14),
                              decoration: InputDecoration(
                                labelText: 'Password (Date of Birth)',
                                hintText: 'DD-MM-YYYY', // Helpful instruction for students
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: EduComponents.icon(
                                    context: context,
                                    iconData: const SolarIcon(SolarIcons.Lock, weight: SolarIconWeight.outline),
                                    size: 20,
                                    color: EduDesignTokens.slate400,
                                  ),
                                ),
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _isPasswordObscured = !_isPasswordObscured;
                                    });
                                  },
                                  icon: EduComponents.icon(
                                    context: context,
                                    iconData: _isPasswordObscured
                                        ? const SolarIcon(SolarIcons.EyeClosed, weight: SolarIconWeight.outline)
                                        : const SolarIcon(SolarIcons.Eye, weight: SolarIconWeight.outline),
                                    size: 20,
                                    color: EduDesignTokens.slate400,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your Date of Birth as password';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    _isLoading
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12.0),
                              child: CircularProgressIndicator(color: theme.primaryColor),
                            ),
                          )
                        : EduComponents.primaryGradientButton(
                            context: context,
                            onPressed: _handleLogin,
                            child: const Text(
                              'Sign In',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
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
}