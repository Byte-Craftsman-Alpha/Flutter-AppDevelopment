import 'package:supabase_flutter/supabase_flutter.dart';
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
      // 💡 1. Query 'StudentDetails' matching the raw String roll number first (since Roll_No is text)
      dynamic response = await Supabase.instance.client
          .from('StudentDetails') 
          .select()
          .eq('Roll_No', rollNumber) 
          .maybeSingle(); 

      // 💡 2. Fallback: If no match found, try querying as parsed Integer (in case of int8 datatype)
      if (response == null) {
        final parsedRoll = int.tryParse(rollNumber);
        if (parsedRoll != null) {
          response = await Supabase.instance.client
              .from('StudentDetails') 
              .select()
              .eq('Roll_No', parsedRoll)
              .maybeSingle();
        }
      }

      // 💡 3. Validate roll number existence
      if (response == null) {
        // Enhanced diagnostic tip for the developer
        _showErrorSnackBar(
          'No account found. If the record exists, verify that your Supabase Row Level Security (RLS) policy allows read/SELECT access.',
          isLongDuration: true,
        );
        return;
      }

      // 💡 4. Validate Date of Birth match (representing the student password)
      final String correctDoB = (response['dob'] ?? 
                                 response['DOB'] ?? 
                                 response['DoB'] ?? 
                                 response['Date_of_Birth'] ?? 
                                 '').toString().trim();
                                 
      // Normalize both inputs by removing hyphens, slashes, and spaces (e.g., "05-11-2006" -> "05112006")
      final cleanEntered = enteredPassword.replaceAll(RegExp(r'[^0-9]'), '');
      final cleanCorrect = correctDoB.replaceAll(RegExp(r'[^0-9]'), '');

      if (cleanEntered != cleanCorrect && enteredPassword != correctDoB) {
        _showErrorSnackBar('Incorrect Date of Birth. Please check and try again.');
        return;
      }

      // 💡 5. Normalize the database keys to match what UserModel.fromMap expects
      final normalizedResponse = {
        'id': response['Roll_No']?.toString() ?? '',
        'name': (response['Name'] ?? response['name'] ?? '').toString(),
        'roll_number': (response['Roll_No'] ?? response['roll_number'] ?? '').toString(),
        'email': (response['Email'] ?? response['email'])?.toString(),
        'department': (response['Programme'] ?? response['department'])?.toString(),
        'dob': correctDoB,
        'Mobile_No': (response['Mobile_No'] ?? response['mobile_no'])?.toString(),
        'Aadhaar': (response['Aadhaar'] ?? response['aadhaar'])?.toString(),
        'enrollment_no': (response['Enrollment No'] ?? response['Enrollment_No'])?.toString(),
        'apaar_id': (response['Apaar_ID'] ?? response['Apaar ID'])?.toString(),
        'address': (response['Address'] ?? response['address'])?.toString(),
        'category': (response['Category'] ?? response['category'])?.toString(),
        'gender': (response['Gender'] ?? response['gender'])?.toString(),
        'father_name': (response['Father_Name'] ?? response['father_name'])?.toString(),
        'mother_name': (response['Mother_Name'] ?? response['mother_name'])?.toString(),
        'semester': (response['Semester'] ?? response['semester'])?.toString(),
      };

      // Map normalized data safely into our clean model class
      // 💡 5. Map explicitly using strict string key lookups directly into your UserModel constructor parameters
      // This completely shields your parsing logic from R8/ProGuard obfuscation!
      final user = UserModel(
        id: response['Roll_No']?.toString() ?? '',
        name: (response['Name'] ?? response['name'] ?? '').toString(),
        rollNumber: (response['Roll_No'] ?? response['roll_number'] ?? '').toString(),
        email: (response['Email'] ?? response['email'])?.toString() ?? '',
        department: (response['Programme'] ?? response['department'])?.toString() ?? '',
        dob: correctDoB,
        mobileNo: (response['Mobile_No'] ?? response['mobile_no'])?.toString() ?? '',
        aadhaar: (response['Aadhaar'] ?? response['aadhaar'])?.toString() ?? '',
        enrollmentNo: (response['Enrollment No'] ?? response['Enrollment_No'])?.toString() ?? '',
        apaarId: (response['Apaar_ID'] ?? response['Apaar ID'])?.toString() ?? '',
        address: (response['Address'] ?? response['address'])?.toString() ?? '',
        category: (response['Category'] ?? response['category'])?.toString() ?? '',
        gender: (response['Gender'] ?? response['gender'])?.toString() ?? '',
        fatherName: (response['Father_Name'] ?? response['father_name'])?.toString() ?? '',
        motherName: (response['Mother_Name'] ?? response['mother_name'])?.toString() ?? '',
        semester: (response['Semester'] ?? response['semester'])?.toString() ?? '',
      );

      // 💡 6. Store user session persistently to disk
      await AuthService.saveSession(user);

      // 💡 7. Route user into main Dashboard and clear history stack
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const MyHomePage(title: 'EduPortal'),
          ),
        );
      }
    } on PostgrestException catch (e) {
      _showErrorSnackBar('Database Connection Error: ${e.message}');
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred during sign in.');
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
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
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