import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Primer-inspired light / dark palettes (simplified for M0).
class AppThemes {
  static const _primerBlue = Color(0xFF0969DA);
  static const _primerBlueDark = Color(0xFF2F81F7);
  static const _canvasLight = Color(0xFFFFFFFF);
  static const _canvasDark = Color(0xFF0D1117);
  static const _fgLight = Color(0xFF1F2328);
  static const _fgDark = Color(0xFFE6EDF3);
  static const _mutedLight = Color(0xFF656D76);
  static const _mutedDark = Color(0xFF8B949E);
  static const _borderLight = Color(0xFFD0D7DE);
  static const _borderDark = Color(0xFF30363D);
  static const _subtleLight = Color(0xFFF6F8FA);
  static const _subtleDark = Color(0xFF161B22);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.light(
          primary: _primerBlue,
          onPrimary: Colors.white,
          surface: _canvasLight,
          onSurface: _fgLight,
          onSurfaceVariant: _mutedLight,
          outline: _borderLight,
          surfaceContainerHighest: _subtleLight,
        ),
        scaffoldBackgroundColor: _canvasLight,
        appBarTheme: const AppBarTheme(
          backgroundColor: _subtleLight,
          foregroundColor: _fgLight,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        cardTheme: CardThemeData(
          color: _canvasLight,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: _borderLight),
          ),
        ),
        dividerColor: _borderLight,
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: _primerBlueDark,
          onPrimary: Colors.white,
          surface: _canvasDark,
          onSurface: _fgDark,
          onSurfaceVariant: _mutedDark,
          outline: _borderDark,
          surfaceContainerHighest: _subtleDark,
        ),
        scaffoldBackgroundColor: _canvasDark,
        appBarTheme: const AppBarTheme(
          backgroundColor: _subtleDark,
          foregroundColor: _fgDark,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        cardTheme: CardThemeData(
          color: _subtleDark,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: _borderDark),
          ),
        ),
        dividerColor: _borderDark,
      );
}

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
