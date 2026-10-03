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

  /// Creates light [ThemeData] using either [dynamicColorScheme] or fallback brand seed.
  static ThemeData createLightTheme(ColorScheme? dynamicColorScheme) {
    final colorScheme = dynamicColorScheme != null
        ? dynamicColorScheme.harmonized()
        : ColorScheme.fromSeed(
            seedColor: defaultLightSeed,
            brightness: Brightness.light,
          );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
    );
  }

  /// Creates dark [ThemeData] using either [dynamicColorScheme] or fallback brand seed.
  static ThemeData createDarkTheme(ColorScheme? dynamicColorScheme) {
    final colorScheme = dynamicColorScheme != null
        ? dynamicColorScheme.harmonized()
        : ColorScheme.fromSeed(
            seedColor: defaultDarkSeed,
            brightness: Brightness.dark,
          );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
    );
  }
}
