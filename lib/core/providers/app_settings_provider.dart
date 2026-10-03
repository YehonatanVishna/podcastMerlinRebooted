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
  Future<void>? _loadFuture;
  final List<AppSettings Function(AppSettings)> _pendingTransforms = [];

  AppSettingsNotifier(this._storage, this._ref) : super(const AppSettings()) {
    _loadFuture = _loadSettings();
  }

  bool get isLoaded => _isLoaded;

  Future<void> ensureLoaded() async {
    if (_loadFuture != null && !_isLoaded) {
      await _loadFuture;
    }
  }

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

      // Check legacy individual keys for backward-compatibility if JSON didn't exist
      if (jsonStr == null || jsonStr.isEmpty) {
        final legacyValues = await Future.wait([
          _storage.read(SecureStorageService.keyRewindDuration),
          _storage.read(SecureStorageService.keyFastForwardDuration),
          _storage.read(SecureStorageService.keyPodcastIndexApiKey),
          _storage.read(SecureStorageService.keyPodcastIndexApiSecret),
          _storage.read(SecureStorageService.keyDeviceId),
        ]);
        final rew = legacyValues[0];
        final ff = legacyValues[1];
        final piKey = legacyValues[2];
        final piSecret = legacyValues[3];
        final devId = legacyValues[4];

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
      }

      if (!mounted) return;
      if (_pendingTransforms.isNotEmpty) {
        state = _pendingTransforms.fold(loaded, (current, transform) => transform(current));
        _pendingTransforms.clear();
      } else {
        state = loaded;
      }
      _isLoaded = true;

      // Sync settings with audio handler
      try {
        final audioHandler = _ref.read(audioHandlerProvider);
        audioHandler.setSeekDurations(rewind: state.rewindDurationSeconds, fastForward: state.fastForwardDurationSeconds);
        audioHandler.setDefaultSpeed(state.defaultPlaybackSpeed);
        audioHandler.setAutoAdvance(state.autoAdvanceQueue);
        audioHandler.setMarkPlayedThreshold(state.markAsPlayedThresholdSeconds);
        audioHandler.setAutoFocusAction(state.audioFocusLossAction);
        audioHandler.setSleepTimerFadeDuration(state.sleepTimerFadeOutSeconds);
        audioHandler.setSkipSilence(state.skipSilence);
        audioHandler.setAutoDeleteAfterPlay(state.autoDeleteAfterPlay);
      } catch (_) {}
    } catch (e) {
      if (kDebugMode) print('Failed loading app settings: $e');
    } finally {
      _isLoaded = true;
    }
  }

  Future<void> updateSettings(AppSettings newSettings) => _update((_) => newSettings);

  Future<void> _update(AppSettings Function(AppSettings current) transform) async {
    state = transform(state);
    if (!_isLoaded) {
      _pendingTransforms.add(transform);
      await ensureLoaded();
    }
    if (!mounted) return;
    await _persist(state);
    _propagateToServices(state);
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
  void setThemeMode(AppThemeMode mode) => _update((s) => s.copyWith(themeMode: mode));
  void setAccentColor(AppAccentColor color) => _update((s) => s.copyWith(accentColor: color, useDynamicColor: false));
  void setUseDynamicColor(bool useDynamic) => _update((s) => s.copyWith(useDynamicColor: useDynamic));
  void setDefaultLandingTab(DefaultLandingTab tab) => _update((s) => s.copyWith(defaultLandingTab: tab));
  void setCompactEpisodeRows(bool compact) => _update((s) => s.copyWith(compactEpisodeRows: compact));
  void setDefaultEpisodeSort(EpisodeSortOrder sort) => _update((s) => s.copyWith(defaultEpisodeSort: sort));
  void setHideCompletedEpisodes(bool hide) => _update((s) => s.copyWith(hideCompletedEpisodes: hide));

  void setDefaultPlaybackSpeed(double speed) => _update((s) => s.copyWith(defaultPlaybackSpeed: speed));
  void setAutoAdvanceQueue(bool autoAdvance) => _update((s) => s.copyWith(autoAdvanceQueue: autoAdvance));
  void setMarkAsPlayedThresholdSeconds(int sec) => _update((s) => s.copyWith(markAsPlayedThresholdSeconds: sec));
  void setAutoFocusLossAction(AutoFocusLossAction action) => _update((s) => s.copyWith(audioFocusLossAction: action));
  void setSleepTimerFadeOutSeconds(int sec) => _update((s) => s.copyWith(sleepTimerFadeOutSeconds: sec));
  void setSkipSilence(bool skip) => _update((s) => s.copyWith(skipSilence: skip));
  void setSeekDurations({int? rewind, int? fastForward}) => _update((s) => s.copyWith(
    rewindDurationSeconds: rewind ?? s.rewindDurationSeconds,
    fastForwardDurationSeconds: fastForward ?? s.fastForwardDurationSeconds,
  ));

  void setDownloadWifiOnly(bool wifiOnly) => _update((s) => s.copyWith(downloadWifiOnly: wifiOnly));
  void setMaxConcurrentDownloads(int max) => _update((s) => s.copyWith(maxConcurrentDownloads: max));
  void setAutoDeletePlayed(AutoDeletePlayedPolicy policy) => _update((s) => s.copyWith(
    autoDeletePlayed: policy,
    autoDeleteAfterPlay: policy != AutoDeletePlayedPolicy.never,
  ));
  void setAutoDeleteAfterPlay(bool enabled) => _update((s) {
    final newPolicy = enabled
        ? (s.autoDeletePlayed == AutoDeletePlayedPolicy.never
            ? AutoDeletePlayedPolicy.immediately
            : s.autoDeletePlayed)
        : AutoDeletePlayedPolicy.never;
    return s.copyWith(
      autoDeleteAfterPlay: enabled,
      autoDeletePlayed: newPolicy,
    );
  });
  void setAutoDownloadNewEpisodes(bool auto) => _update((s) => s.copyWith(autoDownloadNewEpisodes: auto));
  void setAutoDownloadMaxPerShow(int max) => _update((s) => s.copyWith(autoDownloadMaxPerShow: max));
  void setAutoDownloadLastNEpisodes(bool auto) => setAutoDownloadNewEpisodes(auto);
  void setAutoDownloadEpisodesPerShow(int max) => setAutoDownloadMaxPerShow(max);
  void setMaxStorageQuotaGb(int quota) => _update((s) => s.copyWith(maxStorageQuotaGb: quota));
  void setCustomDownloadPath(String? path) => _update((s) => s.copyWith(
    customDownloadPath: path,
    clearCustomDownloadPath: path == null,
  ));

  void setSyncOnLaunch(bool sync) => _update((s) => s.copyWith(syncOnLaunch: sync));
  void setPeriodicSyncIntervalMinutes(int mins) => _update((s) => s.copyWith(periodicSyncIntervalMinutes: mins));
  void setSyncConflictPolicy(SyncConflictPolicy policy) => _update((s) => s.copyWith(syncConflictPolicy: policy));
  void setDeviceId(String id) => _update((s) => s.copyWith(deviceId: id));
  void setPreferredSearchProvider(PreferredSearchProvider prov) => _update((s) => s.copyWith(preferredSearchProvider: prov));
  void setPodcastIndexCredentials(String key, String secret) => _update((s) => s.copyWith(
    podcastIndexApiKey: key,
    podcastIndexApiSecret: secret,
  ));
}

final appSettingsProvider = StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return AppSettingsNotifier(storage, ref);
});
