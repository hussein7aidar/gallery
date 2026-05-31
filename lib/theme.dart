import 'package:flutter/material.dart';

/// A clean, Honor-gallery-style theme: light surfaces, soft rounded thumbnails
/// and an unobtrusive app bar. Supports light and dark.
class AppTheme {
  static const _seed = Color(0xFF3C7DFF);

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
      ),
    );
  }

  /// Corner radius used for album covers and photo cells.
  static const double tileRadius = 16;
}
