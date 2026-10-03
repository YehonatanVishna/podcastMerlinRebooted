import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

/// Provides application-wide light and dark theme configurations,
/// supporting both OS-level dynamic colors and default brand seed colors.
class AppTheme {
  const AppTheme._();

  /// Default brand seed color for light mode.
  static const Color defaultLightSeed = Color(0xFF6750A4);

  /// Default brand seed color for dark mode.
  static const Color defaultDarkSeed = Color(0xFFD0BCFF);

  /// Creates light [ThemeData] using either [dynamicColorScheme] or brand [seedColor].
  static ThemeData createLightTheme(ColorScheme? dynamicColorScheme, {Color? seedColor}) {
    final colorScheme = dynamicColorScheme != null
        ? dynamicColorScheme.harmonized()
        : ColorScheme.fromSeed(
            seedColor: seedColor ?? defaultLightSeed,
            brightness: Brightness.light,
          );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
    );
  }

  /// Creates dark [ThemeData] using either [dynamicColorScheme] or brand [seedColor].
  static ThemeData createDarkTheme(ColorScheme? dynamicColorScheme, {Color? seedColor}) {
    final colorScheme = dynamicColorScheme != null
        ? dynamicColorScheme.harmonized()
        : ColorScheme.fromSeed(
            seedColor: seedColor ?? defaultDarkSeed,
            brightness: Brightness.dark,
          );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
    );
  }

  /// Creates AMOLED true-black [ThemeData] using pure black surfaces and un-tinted navigation bars.
  static ThemeData createAmoledTheme(ColorScheme? dynamicColorScheme, {Color? seedColor}) {
    final baseScheme = dynamicColorScheme != null
        ? dynamicColorScheme.harmonized()
        : ColorScheme.fromSeed(
            seedColor: seedColor ?? defaultDarkSeed,
            brightness: Brightness.dark,
          );

    final amoledScheme = baseScheme.copyWith(
      surface: Colors.black,
      surfaceDim: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0A0A0A),
      surfaceContainer: const Color(0xFF121212),
      surfaceContainerHigh: const Color(0xFF1E1E1E),
      surfaceContainerHighest: const Color(0xFF262626),
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.black,
      canvasColor: Colors.black,
      cardTheme: const CardThemeData(color: Color(0xFF121212)),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.black,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF121212),
      ),
      colorScheme: amoledScheme,
    );
  }
}
