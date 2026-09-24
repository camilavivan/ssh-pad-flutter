import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Primer-inspired light / dark palettes with denser ServerBox-like chrome.
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

  static NavigationRailThemeData _rail(Brightness b) {
    final selected = b == Brightness.dark ? _primerBlueDark : _primerBlue;
    return NavigationRailThemeData(
      backgroundColor: b == Brightness.dark ? _subtleDark : _subtleLight,
      elevation: 0,
      minWidth: 56,
      minExtendedWidth: 160,
      groupAlignment: -0.85,
      labelType: NavigationRailLabelType.selected,
      indicatorColor: selected.withValues(alpha: 0.18),
      selectedIconTheme: IconThemeData(color: selected, size: 22),
      unselectedIconTheme: IconThemeData(
        color: b == Brightness.dark ? _mutedDark : _mutedLight,
        size: 22,
      ),
      selectedLabelTextStyle: TextStyle(
        color: selected,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: b == Brightness.dark ? _mutedDark : _mutedLight,
        fontSize: 11,
      ),
    );
  }

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
          surfaceContainerHigh: const Color(0xFFEEF1F4),
        ),
        scaffoldBackgroundColor: _canvasLight,
        appBarTheme: const AppBarTheme(
          backgroundColor: _subtleLight,
          foregroundColor: _fgLight,
          elevation: 0,
          scrolledUnderElevation: 1,
          titleTextStyle: TextStyle(
            color: _fgLight,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        cardTheme: CardThemeData(
          color: _canvasLight,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: _borderLight),
          ),
        ),
        dividerColor: _borderLight,
        listTileTheme: const ListTileThemeData(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: EdgeInsets.symmetric(horizontal: 12),
        ),
        navigationRailTheme: _rail(Brightness.light),
        chipTheme: ChipThemeData(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          side: const BorderSide(color: _borderLight),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
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
          surfaceContainerHigh: const Color(0xFF1C2128),
        ),
        scaffoldBackgroundColor: _canvasDark,
        appBarTheme: const AppBarTheme(
          backgroundColor: _subtleDark,
          foregroundColor: _fgDark,
          elevation: 0,
          scrolledUnderElevation: 1,
          titleTextStyle: TextStyle(
            color: _fgDark,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        cardTheme: CardThemeData(
          color: _subtleDark,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: _borderDark),
          ),
        ),
        dividerColor: _borderDark,
        listTileTheme: const ListTileThemeData(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: EdgeInsets.symmetric(horizontal: 12),
        ),
        navigationRailTheme: _rail(Brightness.dark),
        chipTheme: ChipThemeData(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          side: const BorderSide(color: _borderDark),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
}

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
