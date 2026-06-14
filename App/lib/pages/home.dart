import 'package:flutter/material.dart';
import 'package:flutty_solar_icons/flutty_solar_icons.dart';
import '../constants/theme.dart'; // Mapped strictly to your centralized design system
import './ProfileScreen.dart'; // Mapped to the updated profile screen
import './CalendarScreen.dart'; // Mapped to the updated calendar screen
import './ChatScreen.dart'; // Mapped to the updated chat screen
import './VaultScreen.dart'; // Mapped to the updated vault screen
import '../services/auth_service.dart'; // Authentication service for user data access

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // 1. Track active tab index
  int _currentTabIndex = 0;

  // 2. State variable for the Counter page
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final theme = Theme.of(context);
    
    final String activeStudentId = AuthService.currentUser?.id ?? "offline_fallback_id";
    final String activeRollNumber = AuthService.currentUser?.rollNumber ?? '';

    // 3. Define the dedicated pages list. 
    final List<Widget> pages = [
      _buildCounterPage(context),
      ChatGroupPage(currentUserId: activeStudentId),
      const CalendarScreen(),
      VaultPage(currentUserId: activeRollNumber),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: systemExt.pageBackground,
        ),
        child: IndexedStack(
          index: _currentTabIndex,
          children: pages,
        ),
      ),

      // 5. Conditional Floating Action Button (Themed for high-contrast slate actions)
      floatingActionButton: _currentTabIndex == 0
          ? FloatingActionButton(
              onPressed: _incrementCounter,
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
              ),
              child: EduComponents.icon(
                context: context,
                iconData: const SolarIcon(SolarIcons.AddCircle, weight: SolarIconWeight.bold),
                color: Colors.white,
              ),
            )
          : null,

      // 6. Modern Material 3 Navigation Bar utilizing Solar Icons & Centralized Theme Extension
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: systemExt.borderNeutral, width: 1.2),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentTabIndex,
          onDestinationSelected: (int index) {
            setState(() {
              _currentTabIndex = index;
            });
          },
          destinations: [
            NavigationDestination(
              icon: EduComponents.icon(
                context: context,
                iconData: const SolarIcon(SolarIcons.HomeN2, weight: SolarIconWeight.outline),
                color: EduDesignTokens.slate400,
              ),
              selectedIcon: EduComponents.icon(
                context: context,
                iconData: const SolarIcon(SolarIcons.HomeN2, weight: SolarIconWeight.bold),
                color: theme.primaryColor,
              ),
              label: 'Home',
            ),
            NavigationDestination(
              icon: EduComponents.icon(
                context: context,
                iconData: const SolarIcon(SolarIcons.ChatRoundDots, weight: SolarIconWeight.outline),
                color: EduDesignTokens.slate400,
              ),
              selectedIcon: EduComponents.icon(
                context: context,
                iconData: const SolarIcon(SolarIcons.ChatRoundDots, weight: SolarIconWeight.bold),
                color: theme.primaryColor,
              ),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: EduComponents.icon(
                context: context,
                iconData: EduIcons.attendanceInactive,
                color: EduDesignTokens.slate400,
              ),
              selectedIcon: EduComponents.icon(
                context: context,
                iconData: EduIcons.attendanceActive,
                color: theme.primaryColor,
              ),
              label: 'Calendar',
            ),
            NavigationDestination(
              icon: EduComponents.icon(
                context: context,
                iconData: const SolarIcon(SolarIcons.FolderWithFiles, weight: SolarIconWeight.outline),
                color: EduDesignTokens.slate400,
              ),
              selectedIcon: EduComponents.icon(
                context: context,
                iconData: const SolarIcon(SolarIcons.FolderWithFiles, weight: SolarIconWeight.bold),
                color: theme.primaryColor,
              ),
              label: 'Files',
            ),
            NavigationDestination(
              icon: EduComponents.icon(
                context: context,
                iconData: EduIcons.profileInactive,
                color: EduDesignTokens.slate400,
              ),
              selectedIcon: EduComponents.icon(
                context: context,
                iconData: EduIcons.profileActive,
                color: theme.primaryColor,
              ),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  // Extracted helper method matching premium portal dashboard cards
  Widget _buildCounterPage(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: EduComponents.card(
          context: context,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? EduDesignTokens.indigo500.withOpacity(0.15)
                        : EduDesignTokens.indigo50,
                    shape: BoxShape.circle,
                  ),
                  child: EduComponents.icon(
                    context: context,
                    iconData: const SolarIcon(SolarIcons.Widget, weight: SolarIconWeight.bold),
                    color: theme.primaryColor,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Interactive Dashboard',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You have pushed the action button this many times:',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  '$_counter',
                  style: textTheme.displayLarge?.copyWith(
                    color: theme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 48,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}