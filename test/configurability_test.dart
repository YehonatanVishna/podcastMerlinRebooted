import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:podcast_merlin_flutter/core/models/gpodder_action.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/downloads/episode_download_service.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/sync/gpodder_api_client.dart';
import 'package:podcast_merlin_flutter/features/sync/secure_storage_service.dart';
import 'package:podcast_merlin_flutter/features/sync/sync_service.dart';
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

class MockNetworkInfoService extends NetworkInfoService {
  NetworkConnectionInfo infoToReturn;
  bool requestPermissionCalled = false;
  bool gpsEnabled = true;

  MockNetworkInfoService([this.infoToReturn = const NetworkConnectionInfo()]);

  @override
  Future<NetworkConnectionInfo> getNetworkInfo({bool requestPermission = false}) async {
    if (requestPermission) {
      requestPermissionCalled = true;
    }
    return infoToReturn;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => gpsEnabled;
}

class MockGPodderApiClient extends GPodderApiClient {
  int pingCount = 0;
  bool pingResult = true;

  @override
  Future<bool> pingServer({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    pingCount++;
    return pingResult;
  }

  @override
  Future<Map<String, dynamic>?> fetchSubscriptions({
    required String serverUrl,
    required String username,
    required String password,
    int sinceTimestamp = 0,
  }) async {
    return {'add': <String>[], 'remove': <String>[], 'timestamp': 100};
  }

  @override
  Future<List<GPodderAction>> fetchEpisodeActions({
    required String serverUrl,
    required String username,
    required String password,
    int sinceTimestamp = 0,
  }) async {
    return [];
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
      expect(settings.normalizePitch, isTrue);
      expect(settings.gpodderNetworkMode, GpodderNetworkRestrictionMode.anyNetwork);
      expect(settings.gpodderAllowedSsid, isEmpty);
      expect(settings.gpodderAllowEthernet, isTrue);
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
        normalizePitch: false,
        gpodderNetworkMode: GpodderNetworkRestrictionMode.specificWifiSsid,
        gpodderAllowedSsid: 'Home-Fiber-5G',
        gpodderAllowEthernet: true,
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
      expect(parsed.normalizePitch, isFalse);
      expect(parsed.gpodderNetworkMode, GpodderNetworkRestrictionMode.specificWifiSsid);
      expect(parsed.gpodderAllowedSsid, 'Home-Fiber-5G');
      expect(parsed.gpodderAllowEthernet, isTrue);
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
        'gpodderNetworkMode': 'satellite_mars_link',
        'normalizePitch': 'not_a_bool',
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
      expect(parsed.defaultPlaybackSpeed, 1.0);
      expect(parsed.markAsPlayedThresholdSeconds, 60);
      expect(parsed.compactEpisodeRows, isFalse);
      expect(parsed.normalizePitch, isTrue);
      expect(parsed.gpodderNetworkMode, GpodderNetworkRestrictionMode.anyNetwork);
    });

    test('fromJson safely ignores legacy podcast index keys and preferredSearchProvider', () {
      final legacyJson = {
        'preferredSearchProvider': 'podcastIndex',
        'podcastIndexApiKey': 'legacy_api_key_123',
        'podcastIndexApiSecret': 'legacy_secret_456',
        'themeMode': 'dark',
        'defaultPlaybackSpeed': 1.5,
      };

      final parsed = AppSettings.fromJson(legacyJson);
      expect(parsed.themeMode, AppThemeMode.dark);
      expect(parsed.defaultPlaybackSpeed, 1.5);
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

      notifier.setNormalizePitch(false);
      expect(container.read(appSettingsProvider).normalizePitch, isFalse);

      notifier.setGpodderNetworkMode(GpodderNetworkRestrictionMode.specificWifiSsid);
      expect(container.read(appSettingsProvider).gpodderNetworkMode, GpodderNetworkRestrictionMode.specificWifiSsid);

      notifier.setGpodderAllowedSsid('Home-Studio-5G');
      expect(container.read(appSettingsProvider).gpodderAllowedSsid, 'Home-Studio-5G');

      notifier.setGpodderAllowEthernet(true);
      expect(container.read(appSettingsProvider).gpodderAllowEthernet, isTrue);

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
      expect(decoded['normalizePitch'], false);
      expect(decoded['gpodderNetworkMode'], 'specificWifiSsid');
      expect(decoded['gpodderAllowedSsid'], 'Home-Studio-5G');
      expect(decoded['gpodderAllowEthernet'], true);

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

      expect(handler.normalizePitch, isTrue);
      expect(handler.pitch, 1.0);
      handler.setSpeed(2.0);
      expect(handler.pitch, 1.0); // speed is 2.0, but normalizePitch is true so pitch is 1.0
      handler.setNormalizePitch(false);
      expect(handler.normalizePitch, isFalse);
      expect(handler.pitch, 2.0); // speed is 2.0 and normalizePitch is false
      handler.setSpeed(0.75);
      expect(handler.pitch, 0.75);
      handler.setSpeed(1.5);
      expect(handler.pitch, 1.5);
      handler.setNormalizePitch(true);
      expect(handler.normalizePitch, isTrue);
      expect(handler.pitch, 1.0);

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

      expect(find.text('Save Device ID'), findsOneWidget);
      expect(find.text('OPML Management'), findsOneWidget);
    });

    testWidgets('Saving empty device ID displays error SnackBar', (tester) async {
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

      // Scroll to view synchronization section where device ID is located
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();

      final deviceIdField = find.widgetWithText(TextField, 'Client Device Identifier');
      expect(deviceIdField, findsOneWidget);

      await tester.enterText(deviceIdField, '   ');
      await tester.pumpAndSettle();

      final saveButton = find.widgetWithText(FilledButton, 'Save Device ID');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('Device ID cannot be empty'), findsOneWidget);
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

    testWidgets('Accent color swatches render horizontally on desktop and tap updates accent color', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

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

      final amberSwatch = find.byTooltip('Amber Gold');
      final purpleSwatch = find.byTooltip('Merlin Purple');
      expect(amberSwatch, findsOneWidget);
      expect(purpleSwatch, findsOneWidget);

      final amberTop = tester.getTopLeft(amberSwatch).dy;
      final purpleTop = tester.getTopLeft(purpleSwatch).dy;
      expect((amberTop - purpleTop).abs() < 1.0, isTrue, reason: 'Swatches should be in a horizontal row, not stacked vertically');

      // 1. When useDynamicColor is true, no accent color swatch should display a checkmark (auto-deselected)
      final swatchCheckmark = find.descendant(
        of: find.byType(CircleAvatar),
        matching: find.byIcon(Icons.check),
      );
      expect(container.read(appSettingsProvider).useDynamicColor, isTrue);
      expect(swatchCheckmark, findsNothing);

      // 2. Tapping an accent color should disable dynamic color and select that swatch
      await tester.tap(amberSwatch);
      await tester.pumpAndSettle();

      expect(container.read(appSettingsProvider).accentColor, AppAccentColor.amber);
      expect(container.read(appSettingsProvider).useDynamicColor, isFalse);
      expect(swatchCheckmark, findsOneWidget);

      // 3. Re-enabling system theme color should auto-deselect the swatch again
      final dynamicColorSwitch = find.widgetWithText(SwitchListTile, 'Use system theme color');
      await tester.ensureVisible(dynamicColorSwitch);
      await tester.tap(dynamicColorSwitch);
      await tester.pumpAndSettle();

      expect(container.read(appSettingsProvider).useDynamicColor, isTrue);
      expect(swatchCheckmark, findsNothing);

      container.dispose();
    });

    testWidgets('Normalize Audio Pitch toggle switches normalizePitch setting', (tester) async {
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

      expect(container.read(appSettingsProvider).normalizePitch, isTrue);

      final pitchTile = find.widgetWithText(SwitchListTile, 'Normalize Audio Pitch');
      expect(pitchTile, findsOneWidget);

      await tester.ensureVisible(pitchTile);
      await tester.tap(pitchTile);
      await tester.pumpAndSettle();

      expect(container.read(appSettingsProvider).normalizePitch, isFalse);

      await tester.tap(pitchTile);
      await tester.pumpAndSettle();

      expect(container.read(appSettingsProvider).normalizePitch, isTrue);

      await tester.pump(const Duration(seconds: 15));
      container.dispose();
    });

    testWidgets('gPodder Network Restriction dropdown switches mode and reveals SSID field', (tester) async {
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

      expect(container.read(appSettingsProvider).gpodderNetworkMode, GpodderNetworkRestrictionMode.anyNetwork);

      // The SSID input should not be visible initially
      expect(find.text('Allowed Wi-Fi SSID / Network Name'), findsNothing);

      // Select Specific Wi-Fi Network (SSID) Only
      final dropdownFinder = find.widgetWithText(DropdownButtonFormField<GpodderNetworkRestrictionMode>, 'gPodder Sync Allowed Networks');
      expect(dropdownFinder, findsOneWidget);

      await tester.ensureVisible(dropdownFinder);
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      final specificOption = find.text('Specific Wi-Fi Network (SSID) Only').last;
      await tester.tap(specificOption);
      await tester.pumpAndSettle();

      expect(container.read(appSettingsProvider).gpodderNetworkMode, GpodderNetworkRestrictionMode.specificWifiSsid);

      // SSID input, Use Current Wi-Fi button, and Ethernet switch should now be visible
      expect(find.text('Allowed Wi-Fi SSID / Network Name'), findsOneWidget);
      expect(find.text('Use Current Wi-Fi'), findsOneWidget);

      final ethernetSwitch = find.widgetWithText(SwitchListTile, 'Also allow on Wired Ethernet');
      expect(ethernetSwitch, findsOneWidget);
      expect(container.read(appSettingsProvider).gpodderAllowEthernet, isTrue);

      await tester.ensureVisible(ethernetSwitch);
      await tester.tap(ethernetSwitch);
      await tester.pumpAndSettle();

      expect(container.read(appSettingsProvider).gpodderAllowEthernet, isFalse);

      await tester.pump(const Duration(seconds: 15));
      container.dispose();
    });
  });

  group('NetworkInfoService Network Gating Tests', () {
    test('cleanSsid cleans surrounding quotes, whitespace, and invalid tokens', () {
      expect(NetworkInfoService.cleanSsid(null), '');
      expect(NetworkInfoService.cleanSsid(''), '');
      expect(NetworkInfoService.cleanSsid('   '), '');
      expect(NetworkInfoService.cleanSsid('"MyHomeNetwork"'), 'MyHomeNetwork');
      expect(NetworkInfoService.cleanSsid("'Office_Wifi'"), 'Office_Wifi');
      expect(NetworkInfoService.cleanSsid('<unknown ssid>'), '');
      expect(NetworkInfoService.cleanSsid('0x'), '');
    });

    test('anyNetwork allows connection regardless of network state', () async {
      final netService = MockNetworkInfoService(
        const NetworkConnectionInfo(isConnected: true, isCellular: true),
      );

      final res = await netService.checkGpodderAccess(
        mode: GpodderNetworkRestrictionMode.anyNetwork,
        allowedSsid: 'HomeWifi',
      );

      expect(res.allowed, isTrue);
      expect(res.reason, isNull);
    });

    test('wifiOrEthernetOnly blocks cellular-only and allows Wi-Fi or Ethernet', () async {
      final cellularOnly = MockNetworkInfoService(
        const NetworkConnectionInfo(isConnected: true, isCellular: true, isWifi: false, isEthernet: false),
      );
      final cellRes = await cellularOnly.checkGpodderAccess(
        mode: GpodderNetworkRestrictionMode.wifiOrEthernetOnly,
        allowedSsid: '',
      );
      expect(cellRes.allowed, isFalse);
      expect(cellRes.reason, contains('cellular'));

      final wifiNet = MockNetworkInfoService(
        const NetworkConnectionInfo(isConnected: true, isWifi: true, isCellular: false),
      );
      final wifiRes = await wifiNet.checkGpodderAccess(
        mode: GpodderNetworkRestrictionMode.wifiOrEthernetOnly,
        allowedSsid: '',
      );
      expect(wifiRes.allowed, isTrue);
      expect(wifiRes.reason, isNull);

      final ethNet = MockNetworkInfoService(
        const NetworkConnectionInfo(isConnected: true, isEthernet: true, isCellular: false),
      );
      final ethRes = await ethNet.checkGpodderAccess(
        mode: GpodderNetworkRestrictionMode.wifiOrEthernetOnly,
        allowedSsid: '',
      );
      expect(ethRes.allowed, isTrue);
    });

    test('specificWifiSsid allows matching SSID and blocks mismatched or missing SSID', () async {
      final homeNet = MockNetworkInfoService(
        const NetworkConnectionInfo(isConnected: true, isWifi: true, ssid: 'Home-Fiber-5G'),
      );

      // Exact match
      final matchRes = await homeNet.checkGpodderAccess(
        mode: GpodderNetworkRestrictionMode.specificWifiSsid,
        allowedSsid: 'Home-Fiber-5G',
      );
      expect(matchRes.allowed, isTrue);

      // Case-insensitive match with whitespace
      final caseRes = await homeNet.checkGpodderAccess(
        mode: GpodderNetworkRestrictionMode.specificWifiSsid,
        allowedSsid: '  home-fiber-5g  ',
      );
      expect(caseRes.allowed, isTrue);

      // Comma-separated list matching one
      final listRes = await homeNet.checkGpodderAccess(
        mode: GpodderNetworkRestrictionMode.specificWifiSsid,
        allowedSsid: 'OfficeWifi, Home-Fiber-5G, Guest',
      );
      expect(listRes.allowed, isTrue);

      // Mismatched SSID
      final mismatchRes = await homeNet.checkGpodderAccess(
        mode: GpodderNetworkRestrictionMode.specificWifiSsid,
        allowedSsid: 'OtherWifi',
      );
      expect(mismatchRes.allowed, isFalse);
      expect(mismatchRes.reason, contains('OtherWifi'));

      // Empty allowedSsid acts as unconfigured / allowed
      final emptyRes = await homeNet.checkGpodderAccess(
        mode: GpodderNetworkRestrictionMode.specificWifiSsid,
        allowedSsid: '',
      );
      expect(emptyRes.allowed, isTrue);

      // Connected without SSID / cellular
      final noSsidNet = MockNetworkInfoService(
        const NetworkConnectionInfo(isConnected: true, isCellular: true, ssid: null),
      );
      final noSsidRes = await noSsidNet.checkGpodderAccess(
        mode: GpodderNetworkRestrictionMode.specificWifiSsid,
        allowedSsid: 'Home-Fiber-5G',
      );
      expect(noSsidRes.allowed, isFalse);

      // Connected to Wi-Fi but SSID unavailable (e.g. Android permissions/location)
      final wifiNoSsidNet = MockNetworkInfoService(
        const NetworkConnectionInfo(isConnected: true, isWifi: true, ssid: null),
      );
      final wifiNoSsidRes = await wifiNoSsidNet.checkGpodderAccess(
        mode: GpodderNetworkRestrictionMode.specificWifiSsid,
        allowedSsid: 'Home-Fiber-5G',
      );
      expect(wifiNoSsidRes.allowed, isFalse);
      expect(wifiNoSsidRes.reason, contains('Location'));

      // Connected to Wi-Fi but GPS disabled
      wifiNoSsidNet.gpsEnabled = false;
      final gpsOffRes = await wifiNoSsidNet.checkGpodderAccess(
        mode: GpodderNetworkRestrictionMode.specificWifiSsid,
        allowedSsid: 'Home-Fiber-5G',
      );
      expect(gpsOffRes.allowed, isFalse);
      expect(gpsOffRes.reason, contains('GPS'));
    });

    test('specificWifiSsid allows wired Ethernet when allowEthernet is true and blocks when false', () async {
      final ethernetNet = MockNetworkInfoService(
        const NetworkConnectionInfo(isConnected: true, isEthernet: true, isWifi: false, ssid: null),
      );

      // When allowEthernet is true (default), wired Ethernet on home network is allowed
      final allowEthRes = await ethernetNet.checkGpodderAccess(
        mode: GpodderNetworkRestrictionMode.specificWifiSsid,
        allowedSsid: 'HomeWifi',
        allowEthernet: true,
      );
      expect(allowEthRes.allowed, isTrue);

      // When allowEthernet is false, wired Ethernet is rejected
      final disallowEthRes = await ethernetNet.checkGpodderAccess(
        mode: GpodderNetworkRestrictionMode.specificWifiSsid,
        allowedSsid: 'HomeWifi',
        allowEthernet: false,
      );
      expect(disallowEthRes.allowed, isFalse);
    });
  });

  group('SyncService Network Gating Integration Tests', () {
    test('performFullSync skips gPodder ping when network constraint is not met', () async {
      final mockStorage = MockSecureStorage();
      await mockStorage.write(SecureStorageService.keyServerUrl, 'https://example.com/gpodder');
      await mockStorage.write(SecureStorageService.keyUsername, 'merlin_user');
      await mockStorage.write(SecureStorageService.keyPassword, 'secret_pass');

      final mockApi = MockGPodderApiClient();
      final mockNet = MockNetworkInfoService(
        const NetworkConnectionInfo(isConnected: true, isCellular: true, ssid: null),
      );

      final syncService = SyncService(
        apiClient: mockApi,
        storage: mockStorage,
        networkInfoService: mockNet,
      );
      syncService.updateNetworkConstraints(
        networkMode: GpodderNetworkRestrictionMode.wifiOrEthernetOnly,
        allowedSsid: '',
      );

      final success = await syncService.performFullSync();
      expect(success, isTrue); // Falls back to local feeds refresh
      expect(mockApi.pingCount, equals(0)); // Did NOT ping gPodder server
      expect(syncService.lastFeedWarnings.isNotEmpty, isTrue);
      expect(syncService.lastFeedWarnings.first, contains('gPodder sync skipped'));
    });

    test('pushPendingBacklog returns false immediately when network constraint is not met', () async {
      final mockStorage = MockSecureStorage();
      await mockStorage.write(SecureStorageService.keyServerUrl, 'https://example.com/gpodder');
      await mockStorage.write(SecureStorageService.keyUsername, 'merlin_user');
      await mockStorage.write(SecureStorageService.keyPassword, 'secret_pass');

      final mockApi = MockGPodderApiClient();
      final mockNet = MockNetworkInfoService(
        const NetworkConnectionInfo(isConnected: true, isWifi: true, ssid: 'CoffeeShopWifi'),
      );

      final syncService = SyncService(
        apiClient: mockApi,
        storage: mockStorage,
        networkInfoService: mockNet,
      );
      syncService.updateNetworkConstraints(
        networkMode: GpodderNetworkRestrictionMode.specificWifiSsid,
        allowedSsid: 'HomeWifi',
      );

      final result = await syncService.pushPendingBacklog();
      expect(result, isFalse);
      expect(mockApi.pingCount, equals(0));
    });

    test('pushPendingActions returns false immediately when network constraint is not met', () async {
      final mockStorage = MockSecureStorage();
      await mockStorage.write(SecureStorageService.keyServerUrl, 'https://example.com/gpodder');
      await mockStorage.write(SecureStorageService.keyUsername, 'merlin_user');
      await mockStorage.write(SecureStorageService.keyPassword, 'secret_pass');

      final mockApi = MockGPodderApiClient();
      final mockNet = MockNetworkInfoService(
        const NetworkConnectionInfo(isConnected: true, isCellular: true, ssid: null),
      );

      final syncService = SyncService(
        apiClient: mockApi,
        storage: mockStorage,
        networkInfoService: mockNet,
      );
      syncService.updateNetworkConstraints(
        networkMode: GpodderNetworkRestrictionMode.wifiOrEthernetOnly,
        allowedSsid: '',
      );

      final result = await syncService.pushPendingActions();
      expect(result, isFalse);
    });

    test('performFullSync allows sync on wired Ethernet when specificWifiSsid is configured with allowEthernet: true', () async {
      final mockStorage = MockSecureStorage();
      await mockStorage.write(SecureStorageService.keyServerUrl, 'https://example.com/gpodder');
      await mockStorage.write(SecureStorageService.keyUsername, 'merlin_user');
      await mockStorage.write(SecureStorageService.keyPassword, 'secret_pass');

      final mockApi = MockGPodderApiClient();
      final mockNet = MockNetworkInfoService(
        const NetworkConnectionInfo(isConnected: true, isEthernet: true, isWifi: false, ssid: null),
      );

      final syncService = SyncService(
        apiClient: mockApi,
        storage: mockStorage,
        networkInfoService: mockNet,
      );
      syncService.updateNetworkConstraints(
        networkMode: GpodderNetworkRestrictionMode.specificWifiSsid,
        allowedSsid: 'HomeWifi',
        allowEthernet: true,
      );

      final success = await syncService.performFullSync();
      expect(success, isTrue);
      expect(mockApi.pingCount, equals(1)); // Pinged server successfully over Ethernet!
    });

    test('performFullSync requests permission when specificWifiSsid is active', () async {
      final mockStorage = MockSecureStorage();
      await mockStorage.write(SecureStorageService.keyServerUrl, 'https://example.com/gpodder');
      await mockStorage.write(SecureStorageService.keyUsername, 'merlin_user');
      await mockStorage.write(SecureStorageService.keyPassword, 'secret_pass');

      final mockApi = MockGPodderApiClient();
      final mockNet = MockNetworkInfoService(
        const NetworkConnectionInfo(isConnected: true, isWifi: true, ssid: 'HomeWifi'),
      );

      final syncService = SyncService(
        apiClient: mockApi,
        storage: mockStorage,
        networkInfoService: mockNet,
      );
      syncService.updateNetworkConstraints(
        networkMode: GpodderNetworkRestrictionMode.specificWifiSsid,
        allowedSsid: 'HomeWifi',
      );

      final success = await syncService.performFullSync();
      expect(success, isTrue);
      expect(mockNet.requestPermissionCalled, isTrue);
    });

    test('audio_pitch method channel is called on setNormalizePitch', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final List<MethodCall> methodCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.podcastmerlin.app/audio_pitch'), (call) async {
        methodCalls.add(call);
        return null;
      });

      final handler = MerlinAudioHandler(
        urlLoader: (_) async {},
      );
      await handler.setNormalizePitch(false);
      expect(handler.normalizePitch, isFalse);
      expect(methodCalls.any((call) => call.method == 'setNormalizePitch' && (call.arguments as Map)['normalize'] == false), isTrue);

      await handler.setNormalizePitch(true);
      expect(handler.normalizePitch, isTrue);
      expect(methodCalls.any((call) => call.method == 'setNormalizePitch' && (call.arguments as Map)['normalize'] == true), isTrue);
    });
  });
}
