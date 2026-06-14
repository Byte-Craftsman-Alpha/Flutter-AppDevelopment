import 'package:intl/intl.dart'; // For date formatting
import 'design_system.dart'; // Handles your solar icons globally

// 💡 Crucial: Implement PreferredSizeWidget so the Scaffold accepts it as an appBar
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle = null;
  final String profileInitials;


  const CustomAppBar({
    super.key,
    required this.title,
    required this.profileInitials,
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
              // 1. Menu Button
              // IconButton(
              //   onPressed: () => Scaffold.of(context).openDrawer(),
              //   icon: SolarIcon(
              //     SolarIcons.HamburgerMenu,
              //     size: 24,
              //   ),
              // ),
              // const SizedBox(width: 12),
              
              // 2. Dynamic Text Header Block
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
                        color: Color(0xFF0F172A),
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
              
              // 3. Reusable Avatar Badge
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