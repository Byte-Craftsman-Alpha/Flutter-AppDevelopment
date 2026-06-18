import 'package:flutter/material.dart';
import 'package:flutty_solar_icons/flutty_solar_icons.dart';
import 'package:google_fonts/google_fonts.dart';

/// # EduPortal Custom Theme Extension
///
/// Holds specialized design tokens that do not map naturally to standard Flutter
/// Material properties (like specific CSS-based box shadow stacks, complex gradients,
/// and level-based attendance visualizations).
class EduPortalThemeExtension extends ThemeExtension<EduPortalThemeExtension> {
  // Page / Card Background Gradients
  final Gradient pageBackground;
  final Gradient primaryGradient;
  final Gradient primaryHoverGradient;
  final Gradient studentAccentGradient;
  final Gradient progressBarGradient;

  // Elevation Shadow Stacks (Utilizes Color.withOpacity)
  final List<BoxShadow> authCardShadow;
  final List<BoxShadow> cardBaseShadow;
  final List<BoxShadow> cardHoverShadow;
  final List<BoxShadow> avatarShadow;
  final List<BoxShadow> softBtnShadow;

  // Attendance Heat Map Colors
  final Color attendanceLevel0;
  final Color attendanceLevel1;
  final Color attendanceLevel2;
  final Color attendanceLevel3;
  final Color attendanceLevel4;

  // Specialized Border Colors
  final Color borderNeutral;
  final Color borderFocus;

  // Custom Button Surfaces
  final Color btnSoftBg;
  final Color btnSoftText;
  final Color btnSoftBorder;
  final Color btnDangerBg;
  final Color btnDangerText;
  final Color btnDangerBorder;

  const EduPortalThemeExtension({
    required this.pageBackground,
    required this.primaryGradient,
    required this.primaryHoverGradient,
    required this.studentAccentGradient,
    required this.progressBarGradient,
    required this.authCardShadow,
    required this.cardBaseShadow,
    required this.cardHoverShadow,
    required this.avatarShadow,
    required this.softBtnShadow,
    required this.attendanceLevel0,
    required this.attendanceLevel1,
    required this.attendanceLevel2,
    required this.attendanceLevel3,
    required this.attendanceLevel4,
    required this.borderNeutral,
    required this.borderFocus,
    required this.btnSoftBg,
    required this.btnSoftText,
    required this.btnSoftBorder,
    required this.btnDangerBg,
    required this.btnDangerText,
    required this.btnDangerBorder,
  });

  @override
  EduPortalThemeExtension copyWith({
    Gradient? pageBackground,
    Gradient? primaryGradient,
    Gradient? primaryHoverGradient,
    Gradient? studentAccentGradient,
    Gradient? progressBarGradient,
    List<BoxShadow>? authCardShadow,
    List<BoxShadow>? cardBaseShadow,
    List<BoxShadow>? cardHoverShadow,
    List<BoxShadow>? avatarShadow,
    List<BoxShadow>? softBtnShadow,
    Color? attendanceLevel0,
    Color? attendanceLevel1,
    Color? attendanceLevel2,
    Color? attendanceLevel3,
    Color? attendanceLevel4,
    Color? borderNeutral,
    Color? borderFocus,
    Color? btnSoftBg,
    Color? btnSoftText,
    Color? btnSoftBorder,
    Color? btnDangerBg,
    Color? btnDangerText,
    Color? btnDangerBorder,
  }) {
    return EduPortalThemeExtension(
      pageBackground: pageBackground ?? this.pageBackground,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      primaryHoverGradient: primaryHoverGradient ?? this.primaryHoverGradient,
      studentAccentGradient: studentAccentGradient ?? this.studentAccentGradient,
      progressBarGradient: progressBarGradient ?? this.progressBarGradient,
      authCardShadow: authCardShadow ?? this.authCardShadow,
      cardBaseShadow: cardBaseShadow ?? this.cardBaseShadow,
      cardHoverShadow: cardHoverShadow ?? this.cardHoverShadow,
      avatarShadow: avatarShadow ?? this.avatarShadow,
      softBtnShadow: softBtnShadow ?? this.softBtnShadow,
      attendanceLevel0: attendanceLevel0 ?? this.attendanceLevel0,
      attendanceLevel1: attendanceLevel1 ?? this.attendanceLevel1,
      attendanceLevel2: attendanceLevel2 ?? this.attendanceLevel2,
      attendanceLevel3: attendanceLevel3 ?? this.attendanceLevel3,
      attendanceLevel4: attendanceLevel4 ?? this.attendanceLevel4,
      borderNeutral: borderNeutral ?? this.borderNeutral,
      borderFocus: borderFocus ?? this.borderFocus,
      btnSoftBg: btnSoftBg ?? this.btnSoftBg,
      btnSoftText: btnSoftText ?? this.btnSoftText,
      btnSoftBorder: btnSoftBorder ?? this.btnSoftBorder,
      btnDangerBg: btnDangerBg ?? this.btnDangerBg,
      btnDangerText: btnDangerText ?? this.btnDangerText,
      btnDangerBorder: btnDangerBorder ?? this.btnDangerBorder,
    );
  }

  @override
  EduPortalThemeExtension lerp(ThemeExtension<EduPortalThemeExtension>? other, double t) {
    if (other is! EduPortalThemeExtension) return this;
    return EduPortalThemeExtension(
      pageBackground: Gradient.lerp(pageBackground, other.pageBackground, t)!,
      primaryGradient: Gradient.lerp(primaryGradient, other.primaryGradient, t)!,
      primaryHoverGradient: Gradient.lerp(primaryHoverGradient, other.primaryHoverGradient, t)!,
      studentAccentGradient: Gradient.lerp(studentAccentGradient, other.studentAccentGradient, t)!,
      progressBarGradient: Gradient.lerp(progressBarGradient, other.progressBarGradient, t)!,
      authCardShadow: t < 0.5 ? authCardShadow : other.authCardShadow,
      cardBaseShadow: t < 0.5 ? cardBaseShadow : other.cardBaseShadow,
      cardHoverShadow: t < 0.5 ? cardHoverShadow : other.cardHoverShadow,
      avatarShadow: t < 0.5 ? avatarShadow : other.avatarShadow,
      softBtnShadow: t < 0.5 ? softBtnShadow : other.softBtnShadow,
      attendanceLevel0: Color.lerp(attendanceLevel0, other.attendanceLevel0, t)!,
      attendanceLevel1: Color.lerp(attendanceLevel1, other.attendanceLevel1, t)!,
      attendanceLevel2: Color.lerp(attendanceLevel2, other.attendanceLevel2, t)!,
      attendanceLevel3: Color.lerp(attendanceLevel3, other.attendanceLevel3, t)!,
      attendanceLevel4: Color.lerp(attendanceLevel4, other.attendanceLevel4, t)!,
      borderNeutral: Color.lerp(borderNeutral, other.borderNeutral, t)!,
      borderFocus: Color.lerp(borderFocus, other.borderFocus, t)!,
      btnSoftBg: Color.lerp(btnSoftBg, other.btnSoftBg, t)!,
      btnSoftText: Color.lerp(btnSoftText, other.btnSoftText, t)!,
      btnSoftBorder: Color.lerp(btnSoftBorder, other.btnSoftBorder, t)!,
      btnDangerBg: Color.lerp(btnDangerBg, other.btnDangerBg, t)!,
      btnDangerText: Color.lerp(btnDangerText, other.btnDangerText, t)!,
      btnDangerBorder: Color.lerp(btnDangerBorder, other.btnDangerBorder, t)!,
    );
  }
}

/// # EduPortal Primitive Design Tokens
///
/// Contains absolute design values based directly on the system's Slate
/// neutrals, gradients, semantic definitions, motion, and spacing rules.
class EduDesignTokens {
  // --- Colors: Light / Dark Neutrals (Slate) ---
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate800 = Color(0xFF334155);
  static const Color slate900 = Color(0xFF0F172A);
  static const Color slate950 = Color(0xFF020617);

  // --- Colors: Core Brand Indigo & Purple Accents ---
  static const Color indigo50 = Color(0xFFEEF2FF);
  static const Color indigo500 = Color(0xFF6366F1);
  static const Color indigo600 = Color(0xFF4F46E5);
  static const Color indigo700 = Color(0xFF4338CA);
  static const Color purple600 = Color(0xFF9333EA);

  // --- Colors: Success (Emerald) ---
  static const Color emerald50 = Color(0xFFECFDF5);
  static const Color emerald200 = Color(0xFFA7F3D0);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald700 = Color(0xFF047857);

  // --- Colors: Danger (Rose) ---
  static const Color rose50 = Color(0xFFFFF1F2);
  static const Color rose100 = Color(0xFFFFE4E6);
  static const Color rose700 = Color(0xFFBE123C);

  // --- Colors: Info (Blue / Sky) ---
  static const Color blue500 = Color(0xFF3B82F6);
  static const Color sky500 = Color(0xFF0EA5E9);

  // --- Spacing Matrix (Tailwind Scaling Map) ---
  static const double space1 = 4.0;   // Tailwind space-1
  static const double space2 = 8.0;   // Tailwind space-2
  static const double space3 = 12.0;  // Tailwind space-3
  static const double space4 = 16.0;  // Tailwind space-4
  static const double space6 = 24.0;  // Tailwind space-6
  static const double space8 = 32.0;  // Tailwind space-8

  // --- Border Radii ("Softness" Rules) ---
  static const double radiusM = 8.0;
  static const double radiusXl = 12.0;   // Controls, inputs, standard buttons
  static const double radius2xl = 16.0;  // Card surfaces, avatar borders
  static const double radius3xl = 24.0;  // Bottom sheets, specialized branding
  static const double radiusFull = 999.0; // Badges, progress circles

  // --- Animations & Transitions ---
  static const Duration durationFast = Duration(milliseconds: 150);   // Admin buttons
  static const Duration durationNormal = Duration(milliseconds: 200); // Standard micro-interactions
  static const Duration durationSlow = Duration(milliseconds: 300);   // Modals and transitions
}

/// # Centralized Solar Icon Mapping System (using flutty_solar_icons)
///
/// This provides standard naming semantic variables for Solar icons.
/// It maps entirely to standard flutter IconData types for complete cross-platform safety.
class EduIcons {
  // Navigation Bar / Navigation Rails (Inactive Outline state vs Active Bold State)
  static const SolarIcon dashboardInactive = SolarIcon(SolarIcons.Widget, weight: SolarIconWeight.outline);
  static const SolarIcon dashboardActive = SolarIcon(SolarIcons.Widget, weight: SolarIconWeight.bold);

  static const SolarIcon attendanceInactive = SolarIcon(SolarIcons.Calendar, weight: SolarIconWeight.outline);
  static const SolarIcon attendanceActive = SolarIcon(SolarIcons.Calendar, weight: SolarIconWeight.bold);

  static const SolarIcon profileInactive = SolarIcon(SolarIcons.User, weight: SolarIconWeight.outline);
  static const SolarIcon profileActive = SolarIcon(SolarIcons.User, weight: SolarIconWeight.bold);

  static const SolarIcon settingsInactive = SolarIcon(SolarIcons.Settings, weight: SolarIconWeight.outline);
  static const SolarIcon settingsActive = SolarIcon(SolarIcons.Settings, weight: SolarIconWeight.bold);

  // General App Actions & Utilities (strict standard native IconData mappings from flutty_solar_icons)
  static const SolarIcon search = SolarIcon(SolarIcons.Magnifer, weight: SolarIconWeight.outline);
  static const SolarIcon bell = SolarIcon(SolarIcons.Bell, weight: SolarIconWeight.outline);
  static const SolarIcon bellActive = SolarIcon(SolarIcons.BellBing, weight: SolarIconWeight.bold);
  static const SolarIcon logout = SolarIcon(SolarIcons.Logout, weight: SolarIconWeight.outline);
  static const SolarIcon lock = SolarIcon(SolarIcons.Lock, weight: SolarIconWeight.outline);
  static const SolarIcon key = SolarIcon(SolarIcons.Key, weight: SolarIconWeight.outline);
  static const SolarIcon info = SolarIcon(SolarIcons.InfoCircle, weight: SolarIconWeight.outline);
  static const SolarIcon chevronDown = SolarIcon(SolarIcons.AltArrowDown, weight: SolarIconWeight.outline);
  static const SolarIcon chevronRight = SolarIcon(SolarIcons.AltArrowRight, weight: SolarIconWeight.outline);
  static const SolarIcon add = SolarIcon(SolarIcons.AddCircle, weight: SolarIconWeight.outline);
  static const SolarIcon close = SolarIcon(SolarIcons.CloseCircle, weight: SolarIconWeight.outline);

  // Semantic States (Using Solid Bold weights for maximum pop)
  static const SolarIcon success = SolarIcon(SolarIcons.CheckCircle, weight: SolarIconWeight.bold);
  static const SolarIcon danger = SolarIcon(SolarIcons.Danger, weight: SolarIconWeight.bold);
  static const SolarIcon alert = SolarIcon(SolarIcons.InfoSquare, weight: SolarIconWeight.bold);
}

/// # EduPortal Theme Generator
///
/// Consolidates custom design values into accessible system [ThemeData] profiles
/// for both Light Mode (Default) and Dark Mode.
class EduTheme {
  
  /// Generates the standard Light Mode Theme
  static ThemeData get lightTheme {
    final base = ThemeData.light();
    final baseTextTheme = GoogleFonts.publicSansTextTheme(base.textTheme);
    
    return base.copyWith(
      scaffoldBackgroundColor: EduDesignTokens.slate50,
      primaryColor: EduDesignTokens.indigo600,
      cardColor: Colors.white,
      dividerColor: EduDesignTokens.slate200,

      // Light Typography Definitions utilizing GoogleFonts.publicSans
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(fontWeight: FontWeight.bold, color: EduDesignTokens.slate900),
        titleLarge: baseTextTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.bold, color: EduDesignTokens.slate900),
        titleMedium: baseTextTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: EduDesignTokens.slate800),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.normal, color: EduDesignTokens.slate800),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.normal, color: EduDesignTokens.slate500),
        labelSmall: baseTextTheme.labelSmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.06, color: EduDesignTokens.slate400),
      ),

      // Input Decoration Mapping (.minimal-input / .admin-input)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
          borderSide: const BorderSide(color: EduDesignTokens.slate200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
          borderSide: const BorderSide(color: EduDesignTokens.slate200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
          borderSide: const BorderSide(color: EduDesignTokens.indigo500, width: 1.5),
        ),
        labelStyle: const TextStyle(fontSize: 14, color: EduDesignTokens.slate500),
        hintStyle: const TextStyle(fontSize: 14, color: EduDesignTokens.slate400),
      ),

      // Card Element Configuration using CardThemeData
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: EduDesignTokens.slate200),
          borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
        ),
      ),

      // Standard Navigation Bar Theme
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: EduDesignTokens.indigo50,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: EduDesignTokens.slate800),
        ),
      ),

      // Custom Extended Design Systems For Light Mode
      extensions: [
        EduPortalThemeExtension(
          pageBackground: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [EduDesignTokens.slate50, EduDesignTokens.slate100],
          ),
          primaryGradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
          ),
          primaryHoverGradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4F46E5), Color(0xFF4338CA)],
          ),
          studentAccentGradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [EduDesignTokens.indigo500, EduDesignTokens.purple600],
          ),
          progressBarGradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [EduDesignTokens.blue500, EduDesignTokens.purple600],
          ),
          authCardShadow: [
            BoxShadow(
              color: EduDesignTokens.slate900.withOpacity(0.15),
              blurRadius: 80,
              offset: const Offset(0, 30),
            ),
            BoxShadow(
              color: EduDesignTokens.slate900.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
          cardBaseShadow: [
            BoxShadow(
              color: EduDesignTokens.slate900.withOpacity(0.04),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
          cardHoverShadow: [
            BoxShadow(
              color: EduDesignTokens.slate900.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          avatarShadow: [
            BoxShadow(
              color: EduDesignTokens.slate900.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          softBtnShadow: [
            BoxShadow(
              color: EduDesignTokens.slate900.withOpacity(0.06),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
          attendanceLevel0: const Color(0xFFEBEDF0),
          attendanceLevel1: const Color(0xFF9BE9A8),
          attendanceLevel2: const Color(0xFF40C463),
          attendanceLevel3: const Color(0xFF30A14E),
          attendanceLevel4: const Color(0xFF216E39),
          borderNeutral: EduDesignTokens.slate200,
          borderFocus: EduDesignTokens.indigo500,
          btnSoftBg: EduDesignTokens.slate100,
          btnSoftText: EduDesignTokens.slate800,
          btnSoftBorder: EduDesignTokens.slate200,
          btnDangerBg: EduDesignTokens.rose50,
          btnDangerText: EduDesignTokens.rose700,
          btnDangerBorder: EduDesignTokens.rose100,
        ),
      ],
    );
  }

  /// Generates the Dark Mode Theme (Optimized Slate & High-Contrast Accents)
  static ThemeData get darkTheme {
    final base = ThemeData.dark();
    final baseTextTheme = GoogleFonts.publicSansTextTheme(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: EduDesignTokens.slate950,
      primaryColor: EduDesignTokens.indigo500,
      cardColor: EduDesignTokens.slate900,
      dividerColor: EduDesignTokens.slate800,

      // Dark Typography Definitions utilizing GoogleFonts.publicSans
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
        titleLarge: baseTextTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        titleMedium: baseTextTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: EduDesignTokens.slate100),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.normal, color: EduDesignTokens.slate100),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.normal, color: EduDesignTokens.slate400),
        labelSmall: baseTextTheme.labelSmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.06, color: EduDesignTokens.slate500),
      ),

      // Input Decoration Mapping (.minimal-input / .admin-input for Dark Mode)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: EduDesignTokens.slate900,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
          borderSide: const BorderSide(color: EduDesignTokens.slate800),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
          borderSide: const BorderSide(color: EduDesignTokens.slate800),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
          borderSide: const BorderSide(color: EduDesignTokens.indigo500, width: 1.5),
        ),
        labelStyle: const TextStyle(fontSize: 14, color: EduDesignTokens.slate400),
        hintStyle: const TextStyle(fontSize: 14, color: EduDesignTokens.slate500),
      ),

      // Card Element Configuration for Dark Mode using CardThemeData
      cardTheme: CardThemeData(
        color: EduDesignTokens.slate900,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: EduDesignTokens.slate800),
          borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
        ),
      ),

      // Navigation Bar Theme for Dark Mode
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: EduDesignTokens.slate900,
        indicatorColor: EduDesignTokens.slate800,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: EduDesignTokens.slate100),
        ),
      ),

      // Custom Extended Design Systems For Dark Mode
      extensions: [
        EduPortalThemeExtension(
          pageBackground: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [EduDesignTokens.slate950, EduDesignTokens.slate900],
          ),
          primaryGradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
          ),
          primaryHoverGradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4F46E5), Color(0xFF4338CA)],
          ),
          studentAccentGradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [EduDesignTokens.indigo500, EduDesignTokens.purple600],
          ),
          progressBarGradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [EduDesignTokens.blue500, EduDesignTokens.purple600],
          ),
          authCardShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 80,
              offset: const Offset(0, 30),
            ),
          ],
          cardBaseShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
          cardHoverShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          avatarShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          softBtnShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
          attendanceLevel0: const Color(0xFF1E293B), 
          attendanceLevel1: const Color(0xFF1B432E), 
          attendanceLevel2: const Color(0xFF10B981),
          attendanceLevel3: const Color(0xFF059669),
          attendanceLevel4: const Color(0xFF047857),
          borderNeutral: EduDesignTokens.slate800,
          borderFocus: EduDesignTokens.indigo500,
          btnSoftBg: EduDesignTokens.slate800,
          btnSoftText: EduDesignTokens.slate100,
          btnSoftBorder: EduDesignTokens.slate800,
          btnDangerBg: const Color(0xFF2D1418), 
          btnDangerText: const Color(0xFFFDA4AF), 
          btnDangerBorder: const Color(0xFF4C1D24),
        ),
      ],
    );
  }
}

/// # Auto-adapting Component System
///
/// Custom component wrappers that automatically select variables based on the
/// current dark/light configuration context.
class EduComponents {
  
  /// Base Minimal/Admin Surface Card Container
  static Widget card({
    required BuildContext context,
    required Widget child,
    bool isHovered = false,
  }) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: systemExt.borderNeutral),
        borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
        boxShadow: isHovered ? systemExt.cardHoverShadow : systemExt.cardBaseShadow,
      ),
      child: child,
    );
  }

  /// Adaptive Icon Widget that automatically pulls system-themed icon styles and colors.
  /// It seamlessly handles both standard native IconData properties and custom flutty_solar_icons
  /// widgets using the standard IconTheme context.
  static Widget icon({
    required BuildContext context,
    required dynamic iconData,
    Color? color,
    double size = 24.0,
  }) {
    final themeColor = color ?? Theme.of(context).textTheme.bodyLarge?.color ?? EduDesignTokens.slate800;
    
    if (iconData is IconData) {
      return Icon(
        iconData,
        size: size,
        color: themeColor,
      );
    } else if (iconData is Widget) {
      return IconTheme(
        data: IconThemeData(
          color: themeColor,
          size: size,
        ),
        child: iconData,
      );
    }
    return const SizedBox.shrink();
  }

  /// Authentic .minimal-btn-primary / Gradient Button implementation
  static Widget primaryGradientButton({
    required BuildContext context,
    required VoidCallback onPressed, 
    required Widget child,
    bool useStudentColors = false,
  }) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    return Container(
      decoration: BoxDecoration(
        gradient: useStudentColors 
            ? systemExt.studentAccentGradient 
            : systemExt.primaryGradient,
        borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
          child: child,
        ),
      ),
    );
  }

  /// Admin Dark Slate / Light Mode Main Primary Button (`.admin-btn-primary`)
  static Widget adminPrimaryButton({
    required BuildContext context,
    required VoidCallback onPressed,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isDark ? EduDesignTokens.slate100 : EduDesignTokens.slate900,
        foregroundColor: isDark ? EduDesignTokens.slate900 : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        elevation: 0,
      ),
      child: child,
    );
  }

  /// Admin Soft Slate Surface Button (`.admin-btn-soft`)
  static Widget adminSoftButton({
    required BuildContext context,
    required VoidCallback onPressed,
    required Widget child,
  }) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    return Container(
      decoration: BoxDecoration(
        boxShadow: systemExt.softBtnShadow,
        borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: systemExt.btnSoftBg,
          foregroundColor: systemExt.btnSoftText,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
            side: BorderSide(color: systemExt.btnSoftBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        child: child,
      ),
    );
  }

  /// Admin Reactive Danger Button Surface (`.admin-btn-danger`)
  static Widget adminDangerButton({
    required BuildContext context,
    required VoidCallback onPressed,
    required Widget child,
  }) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: systemExt.btnDangerBg,
        foregroundColor: systemExt.btnDangerText,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
          side: BorderSide(color: systemExt.btnDangerBorder),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      child: child,
    );
  }

  /// Pill Style Badge Element (`.minimal-badge` / `.admin-pill`)
  static Widget badge({
    required Widget child, 
    Color? backgroundColor,
    Color? textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor ?? EduDesignTokens.slate100,
        borderRadius: BorderRadius.circular(EduDesignTokens.radiusFull),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: textColor ?? EduDesignTokens.slate800, fontSize: 12, fontWeight: FontWeight.w500),
        child: child,
      ),
    );
  }
}