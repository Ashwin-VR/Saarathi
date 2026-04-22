import 'package:flutter/material.dart';

/// Emergency SOS app theme.
/// Primary: deep red (urgency). Secondary: safety blue. Neutral: dark slate.
class AppTheme {
  // ── Brand colors ──────────────────────────────────────────────────────────
  static const Color _primaryRed      = Color(0xFFD32F2F);
  static const Color _primaryRedDark  = Color(0xFFB71C1C);
  static const Color _accentBlue      = Color(0xFF1565C0);
  static const Color _accentBlueDark  = Color(0xFF2196F3); // brighter blue for dark mode contrast
  static const Color _surfaceLight    = Color(0xFFF5F5F5);
  static const Color _surfaceDark     = Color(0xFF1A1A2E);
  static const Color _cardDark        = Color(0xFF16213E);

  // ── Light theme ───────────────────────────────────────────────────────────
  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: _primaryRed,
      brightness: Brightness.light,
      primary: _primaryRed,
      secondary: _accentBlue,
      surface: _surfaceLight,
      error: _primaryRedDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: _surfaceLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: _primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryRed,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1.2),
          elevation: 4,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _primaryRed,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: CircleBorder(),
      ),
      chipTheme: ChipThemeData(
        selectedColor: _primaryRed,
        backgroundColor: Colors.grey.shade200,
        labelStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      extensions: const [AppColors.light],
    );
  }

  // ── Dark theme ────────────────────────────────────────────────────────────
  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: _primaryRed,
      brightness: Brightness.dark,
      primary: _primaryRed,
      secondary: _accentBlueDark,
      surface: _surfaceDark,
      error: _primaryRedDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: _surfaceDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: _cardDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: _cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2A2A4A), width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryRed,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1.2),
          elevation: 6,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _primaryRed,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: CircleBorder(),
      ),
      extensions: const [AppColors.dark],
    );
  }
}

// ── Custom color extension (access via Theme.of(context).extension<AppColors>())
class AppColors extends ThemeExtension<AppColors> {
  final Color success;
  final Color warning;
  final Color sosRed;
  final Color mapBlue;

  const AppColors({
    required this.success,
    required this.warning,
    required this.sosRed,
    required this.mapBlue,
  });

  static const light = AppColors(
    success: Color(0xFF2E7D32),
    warning: Color(0xFFF57F17),
    sosRed:  Color(0xFFD32F2F),
    mapBlue: Color(0xFF1565C0),
  );

  static const dark = AppColors(
    success: Color(0xFF43A047),
    warning: Color(0xFFFFB300),
    sosRed:  Color(0xFFEF5350),
    mapBlue: Color(0xFF1E88E5),
  );

  @override
  AppColors copyWith({Color? success, Color? warning, Color? sosRed, Color? mapBlue}) {
    return AppColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      sosRed:  sosRed  ?? this.sosRed,
      mapBlue: mapBlue ?? this.mapBlue,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      sosRed:  Color.lerp(sosRed,  other.sosRed,  t)!,
      mapBlue: Color.lerp(mapBlue, other.mapBlue, t)!,
    );
  }
}
