import 'constants/design_system.dart'; // Handles material and solar icons globally
import 'services/auth_wrapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/auth_service.dart';
import 'constants/theme.dart'; // Import your Canvas file here

void main() async {
  // 💡 Required to connect platform channels securely
  WidgetsFlutterBinding.ensureInitialized();

  // 💡 Initialize Supabase Client
  await Supabase.initialize(
    url: 'https://kvuvxoajuenszfdanoif.supabase.co',
    publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt2dXZ4b2FqdWVuc3pmZGFub2lmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTU2MjA5NiwiZXhwIjoyMDkxMTM4MDk2fQ.9v882ryLmBv-Laoe8b1WHxfGCwBHe1VY1ufmbId9xjI',
  );

  // 💡 Prefetch persistent storage user session from local disk
  await AuthService.loadSession();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EduPortal',
      debugShowCheckedModeBanner: false,
      theme: EduTheme.lightTheme, 
      darkTheme: EduTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const AuthWrapper(), // Handles routing conditionally automatically
    );
  }
}