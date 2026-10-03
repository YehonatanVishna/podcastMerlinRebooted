import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/downloads/episode_download_service.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/sync/secure_storage_service.dart';
import 'package:podcast_merlin_flutter/features/ui/views/settings_view.dart';

class MockSecureStorage extends SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    return _data[key];
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings Model Tests', () {
    test('Defaults match expected initial values', () {
      const settings = AppSettings();
      expect(settings.themeMode, AppThemeMode.system);
      expect(settings.accentColor, AppAccentColor.purple);
      expect(settings.useDynamicColor, isTrue);
      expect(settings.defaultLandingTab, DefaultLandingTab.catalog);
      expect(settings.compactEpisodeRows, isFalse);
      expect(settings.defaultEpisodeSort, EpisodeSortOrder.newestFirst);
      expect(settings.hideCompletedEpisodes, isFalse);
      expect(settings.defaultPlaybackSpeed, 1.0);
      expect(settings.autoAdvanceQueue, isTrue);
      expect(settings.markAsPlayedThresholdSeconds, 60);
      expect(settings.audioFocusLossAction, AutoFocusLossAction.pauseAndResume);
      expect(settings.sleepTimerFadeOutSeconds, 15);
      expect(settings.skipSilence, isFalse);
      expect(settings.rewindDurationSeconds, 10);
      expect(settings.fastForwardDurationSeconds, 30);
      expect(settings.downloadWifiOnly, isTrue);
      expect(settings.maxConcurrentDownloads, 2);
      expect(settings.autoDeletePlayed, AutoDeletePlayedPolicy.immediately);
      expect(settings.autoDeleteAfterPlay, isTrue);
      expect(settings.autoDownloadNewEpisodes, isFalse);
      expect(settings.autoDownloadLastNEpisodes, isFalse);
      expect(settings.autoDownloadMaxPerShow, 3);
      expect(settings.autoDownloadEpisodesPerShow, 3);
      expect(settings.maxStorageQuotaGb, 10);
      expect(settings.syncOnLaunch, isTrue);
      expect(settings.periodicSyncIntervalMinutes, 180);
      expect(settings.syncConflictPolicy, SyncConflictPolicy.furthestPosition);
      expect(settings.deviceId, 'podcast_merlin_flutter');
      expect(settings.preferredSearchProvider, PreferredSearchProvider.itunes);
    });

    test('Json roundtrip serialization preserves all fields', () {
      const original = AppSettings(
        themeMode: AppThemeMode.amoled,
        accentColor: AppAccentColor.teal,
        useDynamicColor: false,
        defaultLandingTab: DefaultLandingTab.downloads,
        compactEpisodeRows: true,
        defaultEpisodeSort: EpisodeSortOrder.oldestFirst,
        hideCompletedEpisodes: true,
        defaultPlaybackSpeed: 1.5,
        autoAdvanceQueue: false,
        markAsPlayedThresholdSeconds: 90,
        audioFocusLossAction: AutoFocusLossAction.duck,
        sleepTimerFadeOutSeconds: 30,
        skipSilence: true,
        rewindDurationSeconds: 15,
        fastForwardDurationSeconds: 45,
        downloadWifiOnly: false,
        maxConcurrentDownloads: 4,
        autoDeletePlayed: AutoDeletePlayedPolicy.after24h,
        autoDeleteAfterPlay: false,
        maxStorageQuotaGb: 20,
        syncOnLaunch: false,
        periodicSyncIntervalMinutes: 60,
        syncConflictPolicy: SyncConflictPolicy.latestTimestamp,
        deviceId: 'custom_device_id',
        preferredSearchProvider: PreferredSearchProvider.podcastIndex,
        podcastIndexApiKey: 'my_key',
        podcastIndexApiSecret: 'my_secret',
      );

      final jsonMap = original.toJson();
      final parsed = AppSettings.fromJson(jsonMap);

      expect(parsed.themeMode, AppThemeMode.amoled);
      expect(parsed.accentColor, AppAccentColor.teal);
      expect(parsed.useDynamicColor, isFalse);
      expect(parsed.defaultLandingTab, DefaultLandingTab.downloads);
      expect(parsed.compactEpisodeRows, isTrue);
      expect(parsed.defaultEpisodeSort, EpisodeSortOrder.oldestFirst);
      expect(parsed.hideCompletedEpisodes, isTrue);
      expect(parsed.defaultPlaybackSpeed, 1.5);
      expect(parsed.autoAdvanceQueue, isFalse);
      expect(parsed.markAsPlayedThresholdSeconds, 90);
      expect(parsed.audioFocusLossAction, AutoFocusLossAction.duck);
      expect(parsed.sleepTimerFadeOutSeconds, 30);
      expect(parsed.skipSilence, isTrue);
      expect(parsed.rewindDurationSeconds, 15);
      expect(parsed.fastForwardDurationSeconds, 45);
      expect(parsed.downloadWifiOnly, isFalse);
      expect(parsed.maxConcurrentDownloads, 4);
      expect(parsed.autoDeletePlayed, AutoDeletePlayedPolicy.after24h);
      expect(parsed.autoDeleteAfterPlay, isFalse);
      expect(parsed.maxStorageQuotaGb, 20);
      expect(parsed.syncOnLaunch, isFalse);
      expect(parsed.periodicSyncIntervalMinutes, 60);
      expect(parsed.syncConflictPolicy, SyncConflictPolicy.latestTimestamp);
      expect(parsed.deviceId, 'custom_device_id');
      expect(parsed.preferredSearchProvider, PreferredSearchProvider.podcastIndex);
      expect(parsed.podcastIndexApiKey, 'my_key');
      expect(parsed.podcastIndexApiSecret, 'my_secret');
    });

    test('fromJson gracefully falls back to defaults when encountering unknown enum values or corrupted types', () {
      final corruptedJson = {
        'themeMode': 'ultra_neon_rainbow',
        'accentColor': 'iridescent_glow',
        'defaultLandingTab': 'quantum_dimension',
        'defaultEpisodeSort': 'random_shuffle',
        'audioFocusLossAction': 'explode_phone',
        'autoDeletePlayed': 'after_100_years',
        'syncConflictPolicy': 'nuclear_option',
        'preferredSearchProvider': 'napster',
        'defaultPlaybackSpeed': 'not_a_number',
        'markAsPlayedThresholdSeconds': 'invalid_int',
        'compactEpisodeRows': 'not_a_bool',
      };

      final parsed = AppSettings.fromJson(corruptedJson);
      expect(parsed.themeMode, AppThemeMode.system);
      expect(parsed.accentColor, AppAccentColor.purple);
      expect(parsed.defaultLandingTab, DefaultLandingTab.catalog);
      expect(parsed.defaultEpisodeSort, EpisodeSortOrder.newestFirst);
      expect(parsed.audioFocusLossAction, AutoFocusLossAction.pauseAndResume);
      expect(parsed.autoDeletePlayed, AutoDeletePlayedPolicy.immediately);
      expect(parsed.syncConflictPolicy, SyncConflictPolicy.furthestPosition);
      expect(parsed.preferredSearchProvider, PreferredSearchProvider.itunes);
      expect(parsed.defaultPlaybackSpeed, 1.0);
      expect(parsed.markAsPlayedThresholdSeconds, 60);
      expect(parsed.compactEpisodeRows, isFalse);
    });

    test('ThemeMode conversion maps amoled to ThemeMode.dark', () {
      expect(AppThemeMode.system.toThemeMode(), ThemeMode.system);
      expect(AppThemeMode.light.toThemeMode(), ThemeMode.light);
      expect(AppThemeMode.dark.toThemeMode(), ThemeMode.dark);
      expect(AppThemeMode.amoled.toThemeMode(), ThemeMode.dark);
    });
  });

  group('AppSettingsNotifier & Propagation Tests', () {
    test('Notifier updates state and saves to storage', () async {
      final mockStorage = MockSecureStorage();
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(mockStorage),
        ],
      );

      final notifier = container.read(appSettingsProvider.notifier);
      expect(container.read(appSettingsProvider).themeMode, AppThemeMode.system);

      notifier.setThemeMode(AppThemeMode.amoled);
      expect(container.read(appSettingsProvider).themeMode, AppThemeMode.amoled);

      notifier.setDefaultPlaybackSpeed(1.8);
      expect(container.read(appSettingsProvider).defaultPlaybackSpeed, 1.8);

      notifier.setAutoAdvanceQueue(false);
      expect(container.read(appSettingsProvider).autoAdvanceQueue, isFalse);

      notifier.setCompactEpisodeRows(true);
      expect(container.read(appSettingsProvider).compactEpisodeRows, isTrue);

      notifier.setDefaultEpisodeSort(EpisodeSortOrder.oldestFirst);
      expect(container.read(appSettingsProvider).defaultEpisodeSort, EpisodeSortOrder.oldestFirst);

      expect(container.read(appSettingsProvider).autoDeleteAfterPlay, isTrue);
      notifier.setAutoDeleteAfterPlay(false);
      expect(container.read(appSettingsProvider).autoDeleteAfterPlay, isFalse);
      expect(container.read(appSettingsProvider).autoDeletePlayed, AutoDeletePlayedPolicy.never);

      notifier.setAutoDeleteAfterPlay(true);
      expect(container.read(appSettingsProvider).autoDeleteAfterPlay, isTrue);
      expect(container.read(appSettingsProvider).autoDeletePlayed, AutoDeletePlayedPolicy.immediately);

      expect(container.read(appSettingsProvider).autoDownloadNewEpisodes, isFalse);
      notifier.setAutoDownloadNewEpisodes(true);
      expect(container.read(appSettingsProvider).autoDownloadNewEpisodes, isTrue);
      expect(container.read(appSettingsProvider).autoDownloadLastNEpisodes, isTrue);

      notifier.setAutoDownloadMaxPerShow(5);
      expect(container.read(appSettingsProvider).autoDownloadMaxPerShow, 5);
      expect(container.read(appSettingsProvider).autoDownloadEpisodesPerShow, 5);

      // Wait for async persistence to complete
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Verify persistence written to storage
      final storedJson = await mockStorage.read('merlin_app_settings_v1');
      expect(storedJson, isNotNull);
      final decoded = jsonDecode(storedJson!) as Map<String, dynamic>;
      expect(decoded['themeMode'], 'amoled');
      expect(decoded['defaultPlaybackSpeed'], 1.8);
      expect(decoded['autoAdvanceQueue'], false);
      expect(decoded['compactEpisodeRows'], true);
      expect(decoded['defaultEpisodeSort'], 'oldestFirst');
      expect(decoded['autoDeleteAfterPlay'], true);
      expect(decoded['autoDownloadNewEpisodes'], true);
      expect(decoded['autoDownloadMaxPerShow'], 5);

      container.dispose();
    });

    test('AudioHandler responds to configurability setters', () {
      final handler = MerlinAudioHandler(urlLoader: (_) async {});

      expect(handler.autoAdvanceQueue, isTrue);
      handler.setAutoAdvance(false);
      expect(handler.autoAdvanceQueue, isFalse);

      expect(handler.markAsPlayedThresholdSeconds, 60);
      handler.setMarkPlayedThreshold(90);
      expect(handler.markAsPlayedThresholdSeconds, 90);

      expect(handler.audioFocusLossAction, AutoFocusLossAction.pauseAndResume);
      handler.setAutoFocusAction(AutoFocusLossAction.duck);
      expect(handler.audioFocusLossAction, AutoFocusLossAction.duck);

      expect(handler.sleepTimerFadeOutSeconds, 15);
      handler.setSleepTimerFadeDuration(30);
      expect(handler.sleepTimerFadeOutSeconds, 30);

      handler.setDefaultSpeed(2.0);
      expect(handler.playbackState.value.speed, 2.0);

      expect(handler.autoDeleteAfterPlay, isTrue);
      handler.setAutoDeleteAfterPlay(false);
      expect(handler.autoDeleteAfterPlay, isFalse);

      handler.dispose();
    });

    test('EpisodeDownloadService updateConstraints changes concurrent downloads and paths', () {
      final service = EpisodeDownloadService();
      expect(service.maxConcurrentDownloads, 2);
      expect(service.downloadWifiOnly, isTrue);

      service.updateConstraints(
        maxConcurrent: 4,
        wifiOnly: false,
        customPath: '/tmp/test_podcasts',
        autoDelete: AutoDeletePlayedPolicy.after7d,
      );

      expect(service.maxConcurrentDownloads, 4);
      expect(service.downloadWifiOnly, isFalse);
      expect(service.customDownloadPath, '/tmp/test_podcasts');
      expect(service.autoDeletePlayed, AutoDeletePlayedPolicy.after7d);

      service.dispose();
    });
  });

  group('SettingsView Widget Tests', () {
    testWidgets('Renders all 5 categorized configuration sections', (tester) async {
      final mockStorage = MockSecureStorage();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(mockStorage),
            downloadStorageUsageBytesProvider.overrideWith((ref) => Future.value(0)),
            downloadedEpisodesCountProvider.overrideWith((ref) => Future.value(0)),
          ],
          child: const MaterialApp(
            home: SettingsView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check title and sections
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Appearance & Interface'), findsOneWidget);
      expect(find.text('Playback & Controls'), findsOneWidget);
      expect(find.text('Downloads & Storage'), findsOneWidget);
      expect(find.text('Synchronization (Nextcloud / gPodder)'), findsOneWidget);

      // Scroll to view remaining sections
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('Discovery & OPML'), findsOneWidget);
      expect(find.text('Save API Keys & Device ID'), findsOneWidget);
    });

    testWidgets('Tapping theme choice chip updates appSettingsProvider', (tester) async {
      final mockStorage = MockSecureStorage();
      late ProviderContainer container;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container = ProviderContainer(
            overrides: [
              secureStorageProvider.overrideWithValue(mockStorage),
              downloadStorageUsageBytesProvider.overrideWith((ref) => Future.value(0)),
              downloadedEpisodesCountProvider.overrideWith((ref) => Future.value(0)),
            ],
          ),
          child: const MaterialApp(
            home: SettingsView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(container.read(appSettingsProvider).themeMode, AppThemeMode.system);

      // Tap 'AMOLED (True Black)' chip
      final amoledChip = find.text('AMOLED (True Black)');
      expect(amoledChip, findsOneWidget);
      await tester.ensureVisible(amoledChip);
      await tester.tap(amoledChip);
      await tester.pumpAndSettle();

      expect(container.read(appSettingsProvider).themeMode, AppThemeMode.amoled);

      container.dispose();
    });

    testWidgets('Toggling auto-delete episode after play switch updates settings', (tester) async {
      final mockStorage = MockSecureStorage();
      late ProviderContainer container;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container = ProviderContainer(
            overrides: [
              secureStorageProvider.overrideWithValue(mockStorage),
              downloadStorageUsageBytesProvider.overrideWith((ref) => Future.value(0)),
              downloadedEpisodesCountProvider.overrideWith((ref) => Future.value(0)),
            ],
          ),
          child: const MaterialApp(
            home: SettingsView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(container.read(appSettingsProvider).autoDeleteAfterPlay, isTrue);

      final autoDeleteFinder = find.widgetWithText(SwitchListTile, 'Auto-Delete Episode After Play');
      expect(autoDeleteFinder, findsOneWidget);

      await tester.ensureVisible(autoDeleteFinder);
      await tester.tap(autoDeleteFinder);
      await tester.pumpAndSettle();

      expect(container.read(appSettingsProvider).autoDeleteAfterPlay, isFalse);
      expect(container.read(appSettingsProvider).autoDeletePlayed, AutoDeletePlayedPolicy.never);

      container.dispose();
    });

    testWidgets('Toggling auto-download last episodes switch reveals dropdown and updates settings', (tester) async {
      final mockStorage = MockSecureStorage();
      late ProviderContainer container;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container = ProviderContainer(
            overrides: [
              secureStorageProvider.overrideWithValue(mockStorage),
              downloadStorageUsageBytesProvider.overrideWith((ref) => Future.value(0)),
              downloadedEpisodesCountProvider.overrideWith((ref) => Future.value(0)),
            ],
          ),
          child: const MaterialApp(
            home: SettingsView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(container.read(appSettingsProvider).autoDownloadNewEpisodes, isFalse);

      final autoDownloadFinder = find.widgetWithText(SwitchListTile, 'Auto-Download Last Episodes');
      expect(autoDownloadFinder, findsOneWidget);

      await tester.ensureVisible(autoDownloadFinder);
      await tester.tap(autoDownloadFinder);
      await tester.pumpAndSettle();

      expect(container.read(appSettingsProvider).autoDownloadNewEpisodes, isTrue);
      expect(find.text('Episodes Per Subscription to Keep Downloaded'), findsOneWidget);
      expect(find.text('Download Latest Episodes Now'), findsOneWidget);

      container.dispose();
    });
  });
}
