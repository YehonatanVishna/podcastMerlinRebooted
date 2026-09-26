import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/core/theme/app_theme.dart';
import 'package:podcast_merlin_flutter/core/theme/theme_provider.dart';
import 'package:podcast_merlin_flutter/features/sync/secure_storage_service.dart';

class InMemorySecureStorageService extends SecureStorageService {
  final Map<String, String> _store = {};

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    return _store[key];
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }
}

void main() {
  group('AppTheme', () {
    test('createLightTheme falls back to default brand seed when dynamic color is null', () {
      final theme = AppTheme.createLightTheme(null);
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('createDarkTheme falls back to default brand seed when dynamic color is null', () {
      final theme = AppTheme.createDarkTheme(null);
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('createLightTheme uses dynamic color scheme when provided', () {
      const dynamicScheme = ColorScheme.light(primary: Colors.teal);
      final theme = AppTheme.createLightTheme(dynamicScheme);
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.primary, equals(dynamicScheme.harmonized().primary));
    });

    test('createDarkTheme uses dynamic color scheme when provided', () {
      const dynamicScheme = ColorScheme.dark(primary: Colors.deepOrange);
      final theme = AppTheme.createDarkTheme(dynamicScheme);
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.primary, equals(dynamicScheme.harmonized().primary));
    });
  });

  group('ThemeSettingsNotifier', () {
    late InMemorySecureStorageService storage;
    late ThemeSettingsNotifier notifier;

    setUp(() {
      storage = InMemorySecureStorageService();
      notifier = ThemeSettingsNotifier(storage);
    });

    test('defaults to system themeMode and true for useDynamicColor', () {
      expect(notifier.state.themeMode, ThemeMode.system);
      expect(notifier.state.useDynamicColor, isTrue);
    });

    test('setThemeMode updates state and persists', () async {
      await notifier.setThemeMode(ThemeMode.dark);
      expect(notifier.state.themeMode, ThemeMode.dark);
      expect(await storage.read(SecureStorageService.keyThemeMode), 'dark');

      await notifier.setThemeMode(ThemeMode.light);
      expect(notifier.state.themeMode, ThemeMode.light);
      expect(await storage.read(SecureStorageService.keyThemeMode), 'light');
    });

    test('setUseDynamicColor updates state and persists', () async {
      await notifier.setUseDynamicColor(false);
      expect(notifier.state.useDynamicColor, isFalse);
      expect(await storage.read(SecureStorageService.keyUseDynamicColor), 'false');

      await notifier.setUseDynamicColor(true);
      expect(notifier.state.useDynamicColor, isTrue);
      expect(await storage.read(SecureStorageService.keyUseDynamicColor), 'true');
    });

    test('restores saved settings on initialization', () async {
      await storage.write(SecureStorageService.keyThemeMode, 'dark');
      await storage.write(SecureStorageService.keyUseDynamicColor, 'false');

      final newNotifier = ThemeSettingsNotifier(storage);
      await newNotifier.initFuture;

      expect(newNotifier.state.themeMode, ThemeMode.dark);
      expect(newNotifier.state.useDynamicColor, isFalse);
    });
  });
}
