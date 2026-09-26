import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../../features/sync/secure_storage_service.dart';

@immutable
class ThemeSettings {
  final ThemeMode themeMode;
  final bool useDynamicColor;

  const ThemeSettings({
    this.themeMode = ThemeMode.system,
    this.useDynamicColor = true,
  });

  ThemeSettings copyWith({
    ThemeMode? themeMode,
    bool? useDynamicColor,
  }) {
    return ThemeSettings(
      themeMode: themeMode ?? this.themeMode,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeSettings &&
          runtimeType == other.runtimeType &&
          themeMode == other.themeMode &&
          useDynamicColor == other.useDynamicColor;

  @override
  int get hashCode => themeMode.hashCode ^ useDynamicColor.hashCode;
}

class ThemeSettingsNotifier extends StateNotifier<ThemeSettings> {
  final SecureStorageService _storage;
  bool _modeSetByUser = false;
  bool _dynamicColorSetByUser = false;

  late final Future<void> initFuture;

  ThemeSettingsNotifier(this._storage) : super(const ThemeSettings()) {
    initFuture = _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final modeStr = await _storage.read(SecureStorageService.keyThemeMode);
      final dynamicColorStr = await _storage.read(SecureStorageService.keyUseDynamicColor);

      ThemeMode mode = state.themeMode;
      if (!_modeSetByUser && modeStr != null) {
        mode = ThemeMode.values.firstWhere(
          (m) => m.name == modeStr,
          orElse: () => ThemeMode.system,
        );
      }

      bool useDynamic = state.useDynamicColor;
      if (!_dynamicColorSetByUser && dynamicColorStr != null) {
        useDynamic = dynamicColorStr == 'true';
      }

      state = state.copyWith(
        themeMode: mode,
        useDynamicColor: useDynamic,
      );
    } catch (_) {
      // Fallback to default state if storage cannot be read
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _modeSetByUser = true;
    state = state.copyWith(themeMode: mode);
    try {
      await _storage.write(SecureStorageService.keyThemeMode, mode.name);
    } catch (_) {}
  }

  Future<void> setUseDynamicColor(bool useDynamic) async {
    _dynamicColorSetByUser = true;
    state = state.copyWith(useDynamicColor: useDynamic);
    try {
      await _storage.write(SecureStorageService.keyUseDynamicColor, useDynamic.toString());
    } catch (_) {}
  }
}

final themeSettingsProvider =
    StateNotifierProvider<ThemeSettingsNotifier, ThemeSettings>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return ThemeSettingsNotifier(storage);
});
