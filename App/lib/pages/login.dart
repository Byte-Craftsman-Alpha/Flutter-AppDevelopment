import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../constants/design_system.dart'; // Handles your solar icons globally
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

      // Parse the incoming JSON infrastructure maps
      final Map<String, dynamic> responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
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
        // Ensure you update your AuthService signature if you choose to record the JWT on disk!
        await AuthService.saveSession(user);

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
        // Handle specific server-side errors returned by your FastAPI code (400, 401, 404, etc.)
        final errorMessage = responseData['detail'] ?? 'Invalid authorization response.';
        _showErrorSnackBar(errorMessage.toString());
      }
    } catch (e) {
      // Gracefully catch system connection faults, offline network errors, or failed handshakes
      _showErrorSnackBar('Gateway Connection Error: Unable to communicate with authentication server.');
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        duration: Duration(seconds: isLongDuration ? 6 : 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Welcome Back',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to your EduPortal account',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 36),

                  TextFormField(
                    controller: _rollController,
                    keyboardType: TextInputType.number, // Prompt numeric keypad for numeric roll numbers
                    enabled: !_isLoading, // Block typing while querying
                    decoration: InputDecoration(
                      labelText: 'Roll Number',
                      hintText: 'e.g., 2514670010038',
                      prefixIcon: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: SolarIcon(SolarIcons.User, size: 20),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your roll number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),

                  TextFormField(
                    controller: _passwordController,
                    obscureText: _isPasswordObscured,
                    enabled: !_isLoading,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: 'Password (Date of Birth)',
                      hintText: 'DD-MM-YYYY', // Helpful instruction for students
                      prefixIcon: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: SolarIcon(SolarIcons.Lock, size: 20),
                      ),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _isPasswordObscured = !_isPasswordObscured;
                          });
                        },
                        icon: SolarIcon(
                          _isPasswordObscured
                              ? SolarIcons.EyeClosed
                              : SolarIcons.Eye,
                          size: 20,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your Date of Birth as password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 30),

                  _isLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 12.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : ElevatedButton(
                          onPressed: _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}