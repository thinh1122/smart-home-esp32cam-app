import 'package:flutter/material.dart';

class AppColors {
  // Backgrounds
  static const Color bg = Color(0xFF0D0D1A);
  static const Color card = Color(0xFF14142A);
  static const Color cardElevated = Color(0xFF1C1C35);
  static const Color surface = Color(0xFF22223A);

  // Accent
  static const Color accent = Color(0xFF7C6FF7);
  static const Color accentLight = Color(0xFFA5B4FC);
  static const Color accentDim = Color(0xFF3D3A7A);

  // Status
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF38BDF8);

  // Text
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF8E8EA0);
  static const Color textDim = Color(0xFF4A4A6A);

  // Device colors
  static const Color lightColor = Color(0xFFFBBF24);
  static const Color cameraColor = Color(0xFF38BDF8);
  static const Color climateColor = Color(0xFF34D399);
  static const Color securityColor = Color(0xFFFC8181);
}

class AppTheme {
  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accentLight,
      surface: AppColors.card,
      error: AppColors.error,
    ),
    cardColor: AppColors.card,
    fontFamily: 'Roboto',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
      headlineSmall: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      bodyMedium: TextStyle(color: AppColors.textSecondary, fontSize: 14),
      bodySmall: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      labelLarge: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.cardElevated,
      contentTextStyle: TextStyle(color: AppColors.textPrimary),
    ),
    dividerColor: Colors.white10,
    useMaterial3: true,
  );
}

// Shared decoration helpers
class AppDecor {
  static BoxDecoration card({double radius = 24, Color? color, Border? border}) => BoxDecoration(
    color: color ?? AppColors.card,
    borderRadius: BorderRadius.circular(radius),
    border: border,
  );

  static BoxDecoration cardElevated({double radius = 24}) => BoxDecoration(
    color: AppColors.cardElevated,
    borderRadius: BorderRadius.circular(radius),
  );

  static BoxDecoration accentGlow({double radius = 24}) => BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF4F46E5), Color(0xFF7C6FF7)],
    ),
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(color: AppColors.accent.withOpacity(0.3), blurRadius: 16, spreadRadius: 1),
    ],
  );

  static BoxShadow glowShadow(Color color, {double blur = 16}) =>
    BoxShadow(color: color.withOpacity(0.35), blurRadius: blur, spreadRadius: 0);
}
