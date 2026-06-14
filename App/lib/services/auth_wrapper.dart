import 'package:flutter/material.dart';
import 'auth_service.dart';
import '../pages/login.dart'; // Your login page file
import '../pages/home.dart'; // Your home tab layout file

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // 💡 Since AuthService.loadSession() is run and awaited synchronously on app startup in main.dart,
    // we don't need a FutureBuilder here! The login status is resolved instantly.
    if (AuthService.isLoggedIn) {
      return const MyHomePage(title: 'EduPortal'); 
    }

    // If false or undefined, seamlessly load the Login Form screen
    return const LoginScreen();
  }
}