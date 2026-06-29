import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutty_solar_icons/flutty_solar_icons.dart';
import '../constants/theme.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/attendance_db_service.dart';
import 'home.dart';

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
  bool _isLoading = false;

  @override
  void dispose() {
    _rollController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final deviceId = await AuthService.getDeviceId();
      final url = Uri.parse('https://flutter-app-development-mu.vercel.app/api/auth/login');
      
      final response = await http.post(
        url, 
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'roll_number': _rollController.text.trim(),
          'password': _passwordController.text.trim(),
          'device_id': deviceId,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = UserModel.fromMap(data['user']);
        final cloudGroup = data['subscribed_group'];

        // Securely save session, token, and the remotely stored schedule group
        await AuthService.saveSession(user, token: data['access_token'], cloudGroup: cloudGroup);
        
        // Background sync task restoration (pulls latest JSONB from cloud)
        AttendanceDbService.syncFromCloud();

        if (mounted) {
          Navigator.pushReplacement(
            context, 
            MaterialPageRoute(builder: (context) => const MyHomePage(title: 'EduPortal'))
          );
        }
      } else if (response.statusCode == 401 || response.statusCode == 404 || response.statusCode == 400) {
        String errorMessage = 'Invalid credentials. Please check your username and password.';
        try {
          final Map<String, dynamic> responseData = jsonDecode(response.body);
          errorMessage = responseData['detail']?.toString() ?? responseData['message']?.toString() ?? errorMessage;
        } catch (_) {}
        _showErrorSnackBar(errorMessage);
      } else {
        _showErrorSnackBar('Service temporarily unavailable. Please try again later.');
      }
    } on SocketException catch (_) {
      _showErrorSnackBar('No internet connection. Please check your network.', isLongDuration: true);
    } on TimeoutException catch (_) {
      _showErrorSnackBar('Connection timed out. The server is taking too long.', isLongDuration: true);
    } catch (e) {
      debugPrint('Login Error: $e');
      _showErrorSnackBar('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showForgotPasswordSheet() {
    final emailController = TextEditingController();
    final otpController = TextEditingController();
    final newPassController = TextEditingController();
    bool otpSent = false;
    bool isProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(EduDesignTokens.radius3xl))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom, 
              left: 24, right: 24, top: 24
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(otpSent ? 'Reset Password' : 'Forgot Password', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                
                if (!otpSent) ...[
                  Text('Enter your registered email address to receive a secure OTP.', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      labelText: 'Email Address', 
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  EduComponents.primaryGradientButton(
                    context: context,
                    onPressed: isProcessing ? () {} : () async {
                      if (emailController.text.trim().isEmpty) return;
                      setModalState(() => isProcessing = true);
                      try {
                        final res = await http.post(
                          Uri.parse('https://flutter-app-development-mu.vercel.app/api/auth/request-otp'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'email': emailController.text.trim()})
                        ).timeout(const Duration(seconds: 15));
                        
                        if (res.statusCode == 200) {
                          setModalState(() => otpSent = true);
                        } else {
                          _showErrorSnackBar("Email not found or service unavailable.");
                        }
                      } catch (_) { 
                        _showErrorSnackBar("Network error occurred."); 
                      } finally {
                        setModalState(() => isProcessing = false);
                      }
                    },
                    child: isProcessing 
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                      : const Text('Send Reset OTP', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ] else ...[
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '6-Digit OTP', 
                      prefixIcon: const Icon(Icons.password),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: newPassController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'New Password', 
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  EduComponents.primaryGradientButton(
                    context: context,
                    onPressed: isProcessing ? () {} : () async {
                      if (otpController.text.isEmpty || newPassController.text.isEmpty) return;
                      setModalState(() => isProcessing = true);
                      try {
                        final res = await http.post(
                          Uri.parse('https://flutter-app-development-mu.vercel.app/api/auth/reset-password'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'email': emailController.text.trim(),
                            'otp': otpController.text.trim(),
                            'new_password': newPassController.text.trim()
                          })
                        ).timeout(const Duration(seconds: 15));

                        if (res.statusCode == 200) {
                          Navigator.pop(context); // Close bottom sheet
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Password Reset Successfully. Please sign in.', style: TextStyle(fontWeight: FontWeight.bold)),
                              backgroundColor: Theme.of(context).primaryColor,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
                            )
                          );
                        } else {
                          _showErrorSnackBar("Invalid or Expired OTP.");
                        }
                      } catch (_) { 
                        _showErrorSnackBar("Network error occurred."); 
                      } finally {
                        setModalState(() => isProcessing = false);
                      }
                    },
                    child: isProcessing 
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                      : const Text('Update Password', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          );
        }
      )
    );
  }

  void _showErrorSnackBar(String msg, {bool isLongDuration = false}) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            EduComponents.icon(context: context, iconData: EduIcons.danger, color: systemExt.btnDangerText, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(msg, style: TextStyle(fontWeight: FontWeight.bold, color: systemExt.btnDangerText, fontSize: 13))),
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
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: systemExt.pageBackground),
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
                    Center(
                      child: Container(
                        width: 64, height: 64, margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          gradient: systemExt.primaryGradient, 
                          borderRadius: BorderRadius.circular(EduDesignTokens.radius3xl), 
                          boxShadow: systemExt.avatarShadow
                        ),
                        child: EduComponents.icon(context: context, iconData: const SolarIcon(SolarIcons.Widget, weight: SolarIconWeight.bold), color: Colors.white, size: 32),
                      ),
                    ),
                    Text('Welcome Back', textAlign: TextAlign.center, style: textTheme.titleLarge?.copyWith(fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Sign in to your EduPortal account', textAlign: TextAlign.center, style: textTheme.bodyMedium),
                    const SizedBox(height: 36),

                    EduComponents.card(
                      context: context,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _rollController,
                              keyboardType: TextInputType.text,
                              enabled: !_isLoading,
                              decoration: const InputDecoration(
                                labelText: 'Roll Number / Username', 
                                prefixIcon: Icon(Icons.person_outline)
                              ),
                              validator: (v) => v!.trim().isEmpty ? 'Please enter your username' : null,
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _isPasswordObscured,
                              enabled: !_isLoading,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(_isPasswordObscured ? Icons.visibility_off : Icons.visibility),
                                  onPressed: () => setState(() => _isPasswordObscured = !_isPasswordObscured),
                                ),
                              ),
                              validator: (v) => v!.trim().isEmpty ? 'Please enter your password' : null,
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _showForgotPasswordSheet,
                                child: Text('Forgot Password?', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    _isLoading
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12.0),
                              child: CircularProgressIndicator(color: Theme.of(context).primaryColor),
                            )
                          )
                        : EduComponents.primaryGradientButton(
                            context: context, 
                            onPressed: _handleLogin,
                            child: const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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
