import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutty_solar_icons/flutty_solar_icons.dart';
import 'package:google_fonts/google_fonts.dart'; // Ensure this is in pubspec.yaml

// Custom project imports (Assuming these exist in your structure)
import 'design_system.dart';
import '../constants/theme.dart';
import '../constants/widgets.dart';
import '../services/auth_service.dart';
import '../services/crypto_service.dart';
import '../pages/CalendarScreen.dart';
import '../pages/ChatScreen.dart';
import '../pages/VaultScreen.dart';
import '../pages/ProfileScreen.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final String profileInitials;

  const CustomAppBar({
    super.key,
    required this.title,
    required this.profileInitials,
    this.subtitle, // Properly initialized as an optional parameter
  });

  @override
  Widget build(BuildContext context) {
    DateTime now = DateTime.now();
    String formattedDate = DateFormat('EEEE, MMMM d, yyyy').format(now);
    
    return Container(
      // Adds a subtle background color blending with Material 3 app bars
      color: Colors.white,
      // SafeArea prevents notch overlap, padding keeps items beautifully spaced
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Dynamic Text Header Block
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: GoogleFonts.publicSans().fontFamily,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle ?? formattedDate,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: GoogleFonts.publicSans().fontFamily,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Reusable Avatar Badge
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    profileInitials,
                    style: const TextStyle(
                      color: Color(0xFF3730A3),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 💡 Crucial: Tell Flutter how much vertical height your custom widget needs
  @override
  Size get preferredSize => const Size.fromHeight(70.0);
}

class StudentIdCard extends StatelessWidget {
  const StudentIdCard({Key? key}) : super(key: key);

  // Defining the exact colors used in the design
  final Color headerColor = const Color(0xFFB15E17);
  final Color sidebarColor = const Color(0xFFE3CDA4);
  final Color labelColor = const Color(0xFF782516);
  final Color textColor = const Color(0xFF222222);

  @override
  Widget build(BuildContext context) {
    // 💡 MOVED INSIDE BUILD METHOD: context is only available here!
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>();
    final user = AuthService.currentUser;
    final theme = Theme.of(context);

    // Generate the Encrypted String for the QR Code
    final studentMap = {
      'name': user?.name ?? '',
      'roll': user?.rollNumber ?? '',
      'dept': user?.department ?? '',
    };
    final String securePayload = CryptoService.encryptPayload(studentMap);

    return AspectRatio(
      aspectRatio: 1.58, // Standard CR80 ID Card aspect ratio
      child: Card(
        elevation: 8,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          color: Colors.white,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Row(
                  children: [
                    _buildStudentSidebar(),
                    Expanded(
                      // Pass context-dependent variables to the child widget
                      child: _buildMainContent(user, theme, systemExt, securePayload),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: headerColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // University Logo using an Image Asset
          Container(
            width: 45,
            height: 45,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              image: DecorationImage(
                image: AssetImage('assets/images/Logo.png'),
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "DDU Gorakhpur University, Gorakhpur",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14, // Slightly reduced to prevent overflow
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  "दीनदयाल उपाध्याय गोरखपुर विश्वविद्यालय",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentSidebar() {
    return Container(
      width: 32,
      color: sidebarColor,
      alignment: Alignment.center,
      child: const RotatedBox(
        quarterTurns: 3,
        child: Text(
          "STUDENT",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 3.0,
            fontSize: 13,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(dynamic user, ThemeData theme, dynamic systemExt, String securePayload) {
    return Stack(
      children: [
        // Background Watermark
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Opacity(
              opacity: 0.15,
              child: Image.asset(
                'assets/images/Watermark.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        
        // Foreground Details
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Column (QR Code)
              SizedBox(
                width: 90,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildIdCardView(user, theme, systemExt, securePayload),
                        const SizedBox(height: 4),
                        // Signature could go here
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              
              // Right Column (Student Details)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Added null fallback (?? "N/A") to prevent type errors
                    _buildInfoItem("Name", user?.name ?? "N/A"),
                    _buildInfoItem("Department", user?.department ?? "N/A"),
                    Row(
                      children: [
                        Expanded(child: _buildInfoItem("Roll Number", user?.rollNumber ?? "N/A")),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper widget to consistently format the text fields
  Widget _buildInfoItem(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            color: labelColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // Replacing the photo placeholder with a cryptographic QR Code
  Widget _buildIdCardView(dynamic user, ThemeData theme, dynamic systemExt, String securePayload) {
    return Container(
      height: 90,
      width: 90,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400),
        color: Colors.white,
      ),
      child: Center(
        child: securePayload.isNotEmpty
            ? QrImageView(
                data: securePayload,
                version: QrVersions.auto,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                backgroundColor: Colors.white,
              )
            : const Icon(Icons.qr_code, color: Colors.grey, size: 40),
      ),
    );
  }
}