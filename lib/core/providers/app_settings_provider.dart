import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/sync/secure_storage_service.dart';
import 'app_providers.dart';

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  final SecureStorageService _storage;
  final Ref _ref;
  static const String _settingsStorageKey = 'merlin_app_settings_v1';
  bool _isLoaded = false;

  AppSettingsNotifier(this._storage, this._ref) : super(const AppSettings()) {
    _loadSettings();
  }

  bool get isLoaded => _isLoaded;

  Future<void> _loadSettings() async {
    try {
      final jsonStr = await _storage.read(_settingsStorageKey);
      AppSettings loaded = const AppSettings();

      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          loaded = AppSettings.fromJson(map);
        } catch (e) {
          if (kDebugMode) print('Error parsing app settings JSON: $e');
        }
      }

      // Check legacy individual keys for backward-compatibility
      final rew = await _storage.read(SecureStorageService.keyRewindDuration);
      final ff = await _storage.read(SecureStorageService.keyFastForwardDuration);
      final piKey = await _storage.read(SecureStorageService.keyPodcastIndexApiKey);
      final piSecret = await _storage.read(SecureStorageService.keyPodcastIndexApiSecret);
      final devId = await _storage.read(SecureStorageService.keyDeviceId);

      int rewSec = loaded.rewindDurationSeconds;
      int ffSec = loaded.fastForwardDurationSeconds;
      if (rew != null && int.tryParse(rew) != null) rewSec = int.parse(rew);
      if (ff != null && int.tryParse(ff) != null) ffSec = int.parse(ff);

      loaded = loaded.copyWith(
        rewindDurationSeconds: rewSec,
        fastForwardDurationSeconds: ffSec,
        podcastIndexApiKey: (piKey != null && piKey.isNotEmpty) ? piKey : loaded.podcastIndexApiKey,
        podcastIndexApiSecret: (piSecret != null && piSecret.isNotEmpty) ? piSecret : loaded.podcastIndexApiSecret,
        deviceId: (devId != null && devId.isNotEmpty) ? devId : loaded.deviceId,
      );

      if (!mounted) return;
      state = loaded;
      _isLoaded = true;

      // Sync settings with audio handler
      try {
        final audioHandler = _ref.read(audioHandlerProvider);
        audioHandler.setSeekDurations(rewind: rewSec, fastForward: ffSec);
        audioHandler.setDefaultSpeed(loaded.defaultPlaybackSpeed);
        audioHandler.setAutoAdvance(loaded.autoAdvanceQueue);
        audioHandler.setMarkPlayedThreshold(loaded.markAsPlayedThresholdSeconds);
        audioHandler.setAutoFocusAction(loaded.audioFocusLossAction);
        audioHandler.setSleepTimerFadeDuration(loaded.sleepTimerFadeOutSeconds);
        audioHandler.setSkipSilence(loaded.skipSilence);
        audioHandler.setAutoDeleteAfterPlay(loaded.autoDeleteAfterPlay);
      } catch (_) {}
    } catch (e) {
      if (kDebugMode) print('Failed loading app settings: $e');
    }
  }

  Future<void> updateSettings(AppSettings newSettings) async {
    if (!mounted) return;
    state = newSettings;
    await _persist(newSettings);
    _propagateToServices(newSettings);
  }

  void _propagateToServices(AppSettings settings) {
    try {
      final audioHandler = _ref.read(audioHandlerProvider);
      audioHandler.setSeekDurations(
        rewind: settings.rewindDurationSeconds,
        fastForward: settings.fastForwardDurationSeconds,
      );
      audioHandler.setDefaultSpeed(settings.defaultPlaybackSpeed);
      audioHandler.setAutoAdvance(settings.autoAdvanceQueue);
      audioHandler.setMarkPlayedThreshold(settings.markAsPlayedThresholdSeconds);
      audioHandler.setAutoFocusAction(settings.audioFocusLossAction);
      audioHandler.setSleepTimerFadeDuration(settings.sleepTimerFadeOutSeconds);
      audioHandler.setSkipSilence(settings.skipSilence);
      audioHandler.setAutoDeleteAfterPlay(settings.autoDeleteAfterPlay);
    } catch (_) {}

    try {
      final downloadService = _ref.read(episodeDownloadServiceProvider);
      downloadService.updateConstraints(
        wifiOnly: settings.downloadWifiOnly,
        maxConcurrent: settings.maxConcurrentDownloads,
        customPath: settings.customDownloadPath,
      );
    } catch (_) {}
  }

  Future<void> _persist([AppSettings? toPersist]) async {
    final target = toPersist ?? (mounted ? state : null);
    if (target == null) return;
    try {
      final jsonStr = jsonEncode(target.toJson());
      await _storage.write(_settingsStorageKey, jsonStr);

      // Also persist legacy keys for compatibility
      await _storage.write(SecureStorageService.keyRewindDuration, target.rewindDurationSeconds.toString());
      await _storage.write(SecureStorageService.keyFastForwardDuration, target.fastForwardDurationSeconds.toString());
      if (target.podcastIndexApiKey.isNotEmpty) {
        await _storage.write(SecureStorageService.keyPodcastIndexApiKey, target.podcastIndexApiKey);
      }
      if (target.podcastIndexApiSecret.isNotEmpty) {
        await _storage.write(SecureStorageService.keyPodcastIndexApiSecret, target.podcastIndexApiSecret);
      }
      await _storage.write(SecureStorageService.keyDeviceId, target.deviceId);
    } catch (e) {
      if (kDebugMode) print('Failed persisting app settings: $e');
    }
  }

  // Convenience mutators
  void setThemeMode(AppThemeMode mode) => updateSettings(state.copyWith(themeMode: mode));
  void setAccentColor(AppAccentColor color) => updateSettings(state.copyWith(accentColor: color));
  void setDefaultLandingTab(DefaultLandingTab tab) => updateSettings(state.copyWith(defaultLandingTab: tab));
  void setCompactEpisodeRows(bool compact) => updateSettings(state.copyWith(compactEpisodeRows: compact));
  void setDefaultEpisodeSort(EpisodeSortOrder sort) => updateSettings(state.copyWith(defaultEpisodeSort: sort));
  void setHideCompletedEpisodes(bool hide) => updateSettings(state.copyWith(hideCompletedEpisodes: hide));

  void setDefaultPlaybackSpeed(double speed) => updateSettings(state.copyWith(defaultPlaybackSpeed: speed));
  void setAutoAdvanceQueue(bool autoAdvance) => updateSettings(state.copyWith(autoAdvanceQueue: autoAdvance));
  void setMarkAsPlayedThresholdSeconds(int sec) => updateSettings(state.copyWith(markAsPlayedThresholdSeconds: sec));
  void setAutoFocusLossAction(AutoFocusLossAction action) => updateSettings(state.copyWith(audioFocusLossAction: action));
  void setSleepTimerFadeOutSeconds(int sec) => updateSettings(state.copyWith(sleepTimerFadeOutSeconds: sec));
  void setSkipSilence(bool skip) => updateSettings(state.copyWith(skipSilence: skip));
  void setSeekDurations({int? rewind, int? fastForward}) => updateSettings(state.copyWith(
    rewindDurationSeconds: rewind ?? state.rewindDurationSeconds,
    fastForwardDurationSeconds: fastForward ?? state.fastForwardDurationSeconds,
  ));

  void setDownloadWifiOnly(bool wifiOnly) => updateSettings(state.copyWith(downloadWifiOnly: wifiOnly));
  void setMaxConcurrentDownloads(int max) => updateSettings(state.copyWith(maxConcurrentDownloads: max));
  void setAutoDeletePlayed(AutoDeletePlayedPolicy policy) => updateSettings(state.copyWith(
    autoDeletePlayed: policy,
    autoDeleteAfterPlay: policy != AutoDeletePlayedPolicy.never,
  ));
  void setAutoDeleteAfterPlay(bool enabled) {
    final newPolicy = enabled
        ? (state.autoDeletePlayed == AutoDeletePlayedPolicy.never
            ? AutoDeletePlayedPolicy.immediately
            : state.autoDeletePlayed)
        : AutoDeletePlayedPolicy.never;
    updateSettings(state.copyWith(
      autoDeleteAfterPlay: enabled,
      autoDeletePlayed: newPolicy,
    ));
  }
  void setAutoDownloadNewEpisodes(bool auto) => updateSettings(state.copyWith(autoDownloadNewEpisodes: auto));
  void setAutoDownloadMaxPerShow(int max) => updateSettings(state.copyWith(autoDownloadMaxPerShow: max));
  void setAutoDownloadLastNEpisodes(bool auto) => setAutoDownloadNewEpisodes(auto);
  void setAutoDownloadEpisodesPerShow(int max) => setAutoDownloadMaxPerShow(max);
  void setMaxStorageQuotaGb(int quota) => updateSettings(state.copyWith(maxStorageQuotaGb: quota));
  void setCustomDownloadPath(String? path) => updateSettings(state.copyWith(
    customDownloadPath: path,
    clearCustomDownloadPath: path == null,
  ));

  void setSyncOnLaunch(bool sync) => updateSettings(state.copyWith(syncOnLaunch: sync));
  void setPeriodicSyncIntervalMinutes(int mins) => updateSettings(state.copyWith(periodicSyncIntervalMinutes: mins));
  void setSyncConflictPolicy(SyncConflictPolicy policy) => updateSettings(state.copyWith(syncConflictPolicy: policy));
  void setDeviceId(String id) => updateSettings(state.copyWith(deviceId: id));
  void setPreferredSearchProvider(PreferredSearchProvider prov) => updateSettings(state.copyWith(preferredSearchProvider: prov));
  void setPodcastIndexCredentials(String key, String secret) => updateSettings(state.copyWith(
    podcastIndexApiKey: key,
    podcastIndexApiSecret: secret,
  ));
}

final appSettingsProvider = StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return AppSettingsNotifier(storage, ref);
});
