import 'package:flutter/material.dart';

class SenderColorAssigner {
  static final List<Color> _colorPalette = [
    const Color(0xFFE11D48), // Rose Red
    const Color(0xFF2563EB), // Blue
    const Color(0xFF16A34A), // Green
    const Color(0xFFD97706), // Amber Orange
    const Color(0xFF7C3AED), // Purple
    const Color(0xFF0891B2), // Cyan
    const Color(0xFFDB2777), // Pink
    const Color(0xFF4F46E5), // Indigo
  ];

  /// Generates a unique, sticky avatar username color matching string credentials
  static Color getColor(String uniqueSeed) {
    if (uniqueSeed.isEmpty) return const Color(0xFF64748B);
    
    int hash = 0;
    for (int i = 0; i < uniqueSeed.length; i++) {
      hash = uniqueSeed.codeUnitAt(i) + ((hash << 5) - hash);
    }
    
    final index = hash.abs() % _colorPalette.length;
    return _colorPalette[index];
  }
}