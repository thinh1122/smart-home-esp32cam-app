import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier extends ValueNotifier<ThemeMode> {
  static final ThemeNotifier instance = ThemeNotifier._();
  ThemeNotifier._() : super(ThemeMode.dark) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? true;
    value = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> toggle() async {
    value = value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value == ThemeMode.dark);
  }

  bool get isDark => value == ThemeMode.dark;
}

// Dark palette (giữ nguyên)
class AppColors {
  static const Color bg            = Color(0xFF0D0D1A);
  static const Color card          = Color(0xFF14142A);
  static const Color cardElevated  = Color(0xFF1C1C35);
  static const Color surface       = Color(0xFF22223A);

  static const Color accent        = Color(0xFF7C6FF7);
  static const Color accentLight   = Color(0xFFA5B4FC);
  static const Color accentDim     = Color(0xFF3D3A7A);

  static const Color success       = Color(0xFF22C55E);
  static const Color warning       = Color(0xFFF59E0B);
  static const Color error         = Color(0xFFEF4444);
  static const Color info          = Color(0xFF38BDF8);

  static const Color textPrimary   = Colors.white;
  static const Color textSecondary = Color(0xFF8E8EA0);
  static const Color textDim       = Color(0xFF4A4A6A);

  static const Color lightColor    = Color(0xFFFBBF24);
  static const Color cameraColor   = Color(0xFF38BDF8);
  static const Color climateColor  = Color(0xFF34D399);
  static const Color securityColor = Color(0xFFFC8181);
}

// Light palette
class AppColorsLight {
  static const Color bg            = Color(0xFFF2F3F8);
  static const Color card          = Colors.white;
  static const Color cardElevated  = Color(0xFFEEEEF6);
  static const Color surface       = Color(0xFFE8E8F4);

  static const Color accent        = Color(0xFF6C63F0);
  static const Color accentLight   = Color(0xFF6C63F0);
  static const Color accentDim     = Color(0xFFDDDBFB);

  static const Color success       = Color(0xFF16A34A);
  static const Color warning       = Color(0xFFD97706);
  static const Color error         = Color(0xFFDC2626);
  static const Color info          = Color(0xFF0284C7);

  static const Color textPrimary   = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textDim       = Color(0xFF9CA3AF);

  static const Color lightColor    = Color(0xFFD97706);
  static const Color cameraColor   = Color(0xFF0284C7);
  static const Color climateColor  = Color(0xFF059669);
  static const Color securityColor = Color(0xFFDC2626);
}

/// Context-aware color accessor — dùng thay cho AppColors.* trong widgets
class AC {
  final bool dark;
  const AC._(this.dark);

  factory AC.of(BuildContext ctx) =>
      AC._(Theme.of(ctx).brightness == Brightness.dark);

  Color get bg            => dark ? AppColors.bg           : AppColorsLight.bg;
  Color get card          => dark ? AppColors.card         : AppColorsLight.card;
  Color get cardElevated  => dark ? AppColors.cardElevated : AppColorsLight.cardElevated;
  Color get surface       => dark ? AppColors.surface      : AppColorsLight.surface;
  Color get accent        => dark ? AppColors.accent       : AppColorsLight.accent;
  Color get accentLight   => dark ? AppColors.accentLight  : AppColorsLight.accentLight;
  Color get accentDim     => dark ? AppColors.accentDim    : AppColorsLight.accentDim;
  Color get success       => dark ? AppColors.success      : AppColorsLight.success;
  Color get warning       => dark ? AppColors.warning      : AppColorsLight.warning;
  Color get error         => dark ? AppColors.error        : AppColorsLight.error;
  Color get info          => dark ? AppColors.info         : AppColorsLight.info;
  Color get textPrimary   => dark ? AppColors.textPrimary  : AppColorsLight.textPrimary;
  Color get textSecondary => dark ? AppColors.textSecondary: AppColorsLight.textSecondary;
  Color get textDim       => dark ? AppColors.textDim      : AppColorsLight.textDim;
  Color get lightColor    => dark ? AppColors.lightColor   : AppColorsLight.lightColor;
  Color get cameraColor   => dark ? AppColors.cameraColor  : AppColorsLight.cameraColor;
  Color get climateColor  => dark ? AppColors.climateColor : AppColorsLight.climateColor;
  Color get securityColor => dark ? AppColors.securityColor: AppColorsLight.securityColor;
  Color get divider       => dark ? Colors.white10         : Colors.black.withOpacity(0.08);
  Color get border        => dark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.08);
  Color get iconMuted     => dark ? Colors.white38         : Colors.black38;
  Color get iconFaint     => dark ? Colors.white24         : Colors.black26;
  Color get shadowColor   => dark ? Colors.black.withOpacity(0.4) : Colors.black.withOpacity(0.12);
}

class AppTheme {
  static ThemeData get light => ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColorsLight.bg,
    colorScheme: ColorScheme.light(
      primary: AppColorsLight.accent,
      secondary: AppColorsLight.accentLight,
      surface: AppColorsLight.card,
      error: AppColorsLight.error,
    ),
    cardColor: AppColorsLight.card,
    fontFamily: 'Roboto',
    useMaterial3: true,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: AppColorsLight.textPrimary, fontSize: 28, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: AppColorsLight.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
      headlineSmall: TextStyle(color: AppColorsLight.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: AppColorsLight.textPrimary, fontSize: 16),
      bodyMedium: TextStyle(color: AppColorsLight.textSecondary, fontSize: 14),
      bodySmall: TextStyle(color: AppColorsLight.textSecondary, fontSize: 12),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColorsLight.cardElevated,
      contentTextStyle: TextStyle(color: AppColorsLight.textPrimary),
    ),
    dividerColor: Colors.black12,
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColorsLight.accent : Colors.grey),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColorsLight.accent.withOpacity(0.3) : Colors.grey.withOpacity(0.2)),
    ),
  );

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
    useMaterial3: true,
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
  );
}

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
