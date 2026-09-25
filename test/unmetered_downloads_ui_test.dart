import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/core/services/connectivity_service.dart';
import 'package:podcast_merlin_flutter/features/downloads/episode_download_service.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/sync/secure_storage_service.dart';
import 'package:podcast_merlin_flutter/features/ui/views/settings_view.dart';
import 'package:podcast_merlin_flutter/features/ui/views/download_center_view.dart';
import 'package:podcast_merlin_flutter/features/ui/views/episode_list_view.dart';

class FakeSecureStorageService extends SecureStorageService {
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

class FakeEpisodeDownloadService extends Fake implements EpisodeDownloadService {
  final _eventController = StreamController<DownloadTaskEvent>.broadcast();
  final Map<int, DownloadTaskEvent> _tasks = {};
  Episode? lastDownloadedEpisode;

  @override
  Stream<DownloadTaskEvent> get onDownloadEvent => _eventController.stream;

  @override
  Map<int, DownloadTaskEvent> get currentTasks => _tasks;

  @override
  int get activeAndQueuedCount => _tasks.length;

  @override
  bool isEpisodeActive(int episodeId) => false;

  @override
  bool isEpisodeQueued(int episodeId) => false;

  @override
  bool isEpisodePaused(int episodeId) => false;

  @override
  Future<int> getTotalDownloadStorageBytes() async => 1024 * 1024 * 50;

  @override
  Future<void> startDownload(Episode episode) async {
    lastDownloadedEpisode = episode;
  }

  void setTask(int episodeId, DownloadTaskEvent event) {
    _tasks[episodeId] = event;
    _eventController.add(event);
  }

  @override
  void dispose() {
    _eventController.close();
  }
}

class FakeAudioHandler extends Fake implements MerlinAudioHandler {
  final _posController = StreamController<PositionUpdateEvent>.broadcast();

  @override
  Stream<PositionUpdateEvent> get onPositionUpdated => _posController.stream;

  @override
  Episode? get currentEpisode => null;

  @override
  Future<void> setSeekDurations({int? rewind, int? fastForward}) async {}
}

class TestEpisodesNotifier extends StateNotifier<EpisodesState> implements EpisodesNotifier {
  TestEpisodesNotifier(List<Episode> episodes, {EpisodeFilter filter = EpisodeFilter.all})
      : super(
          EpisodesState(
            episodes: episodes,
            isLoading: false,
            isLoadingMore: false,
            hasMore: false,
            filter: filter,
          ),
        );

  @override
  Future<void> loadEpisodes({EpisodeFilter? filter, bool silent = false}) async {}

  @override
  Future<void> loadMoreEpisodes() async {}

  @override
  Future<bool> toggleStar(Episode episode) async => false;

  @override
  Future<void> markAsPlayed(Episode episode, bool isPlayed) async {}

  @override
  Future<void> togglePlayed(Episode episode) async {}

  @override
  Future<void> markMultipleAsPlayed(List<Episode> episodes, bool isPlayed) async {}

  @override
  Future<void> setFilter(EpisodeFilter filter) async {}

  @override
  Future<void> refresh({Podcast? podcast}) async {}

  @override
  void updateEpisodeProgress(String mediaUrl, int position, bool isPlayed) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsView unmetered download switch tests', () {
    testWidgets('Displays unmetered switch tile and toggles state', (tester) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeStorage = FakeSecureStorageService();
      final fakeDownloadService = FakeEpisodeDownloadService();
      final fakeAudioHandler = FakeAudioHandler();
      final mockConnectivity = MockConnectivityService(initialIsUnmetered: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(fakeStorage),
            audioHandlerProvider.overrideWithValue(fakeAudioHandler),
            episodeDownloadServiceProvider.overrideWithValue(fakeDownloadService),
            connectivityServiceProvider.overrideWithValue(mockConnectivity),
            downloadStorageUsageBytesProvider.overrideWith((ref) => Future.value(10485760)),
            downloadedEpisodesCountProvider.overrideWith((ref) => Future.value(3)),
          ],
          child: const MaterialApp(
            home: SettingsView(),
          ),
        ),
      );

      // Pump for initState async load
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Find the SwitchListTile
      final titleFinder = find.text('Download only on unmetered Wi-Fi');
      await tester.ensureVisible(titleFinder);
      await tester.pumpAndSettle();
      expect(titleFinder, findsOneWidget);

      final subtitleFinder = find.text('Prevent downloading episodes over mobile data to save bandwidth.');
      expect(subtitleFinder, findsOneWidget);

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      final switchWidgetBefore = tester.widget<Switch>(switchFinder);
      expect(switchWidgetBefore.value, isFalse);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      final switchWidgetAfter = tester.widget<Switch>(switchFinder);
      expect(switchWidgetAfter.value, isTrue);
    });
  });

  group('DownloadCenterView unmetered queued feedback tests', () {
    testWidgets('Displays waiting for unmetered Wi-Fi status in queue tab', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeDownloadService = FakeEpisodeDownloadService();
      fakeDownloadService.setTask(
        42,
        DownloadTaskEvent(
          episodeId: 42,
          mediaUrl: 'https://example.com/ep42.mp3',
          episodeTitle: 'Test Unmetered Episode',
          status: DownloadStatus.queued,
          error: 'Waiting for unmetered Wi-Fi connection',
        ),
      );

      final fakeAudioHandler = FakeAudioHandler();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioHandlerProvider.overrideWithValue(fakeAudioHandler),
            episodeDownloadServiceProvider.overrideWithValue(fakeDownloadService),
            downloadStorageUsageBytesProvider.overrideWith((ref) => Future.value(0)),
            downloadedEpisodesListProvider.overrideWith((ref) => Future.value([])),
            failedEpisodesListProvider.overrideWith((ref) => Future.value([])),
            activeDownloadsCountProvider.overrideWith((ref) => Stream.value(1)),
            downloadTasksStreamProvider.overrideWith((ref) => Stream.value(fakeDownloadService.currentTasks)),
          ],
          child: const MaterialApp(
            home: DownloadCenterView(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify queued item title is present
      expect(find.text('Test Unmetered Episode'), findsOneWidget);

      // Verify "Waiting for unmetered Wi-Fi connection" is clearly displayed
      expect(find.text('Waiting for unmetered Wi-Fi connection'), findsOneWidget);

      // Verify wifi_off icon is displayed for metered waiting status
      expect(find.byIcon(Icons.wifi_off_rounded), findsWidgets);
    });
  });

  group('EpisodeListView unmetered feedback tests', () {
    final testPodcast = Podcast(
      id: 1,
      rssUrl: 'https://example.com/podcast.xml',
      title: 'Test Podcast',
      description: 'Test Description',
      imageUrl: '',
      link: '',
      lastUpdated: DateTime.now(),
    );

    testWidgets('Shows SnackBar when downloading on metered network with unmetered setting enabled', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const ep = Episode(
        id: 101,
        guid: 'ep-101',
        title: 'Metered Download Episode',
        mediaUrl: 'https://example.com/ep101.mp3',
        description: 'Test Desc',
        imageUrl: '',
        podcastRss: 'https://example.com/podcast.xml',
      );

      final fakeDownloadService = FakeEpisodeDownloadService();
      final fakeAudioHandler = FakeAudioHandler();
      final fakeStorage = FakeSecureStorageService();
      await fakeStorage.setDownloadOnlyOnUnmetered(true);

      // Connection is metered (false)
      final mockConnectivity = MockConnectivityService(initialIsUnmetered: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(fakeStorage),
            audioHandlerProvider.overrideWithValue(fakeAudioHandler),
            episodeDownloadServiceProvider.overrideWithValue(fakeDownloadService),
            connectivityServiceProvider.overrideWithValue(mockConnectivity),
            downloadOnlyOnUnmeteredProvider.overrideWith(
              (ref) => DownloadOnlyOnUnmeteredNotifier(fakeStorage)..state = true,
            ),
            episodesNotifierProvider(1).overrideWith(
              (ref) => TestEpisodesNotifier([ep]),
            ),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: testPodcast),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Metered Download Episode'), findsOneWidget);

      // Tap the download icon button
      final downloadBtnFinder = find.byIcon(Icons.download_outlined);
      expect(downloadBtnFinder, findsOneWidget);

      await tester.tap(downloadBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // SnackBar with waiting message must be displayed
      expect(find.text('Download queued: Waiting for unmetered Wi-Fi connection'), findsOneWidget);
    });

    testWidgets('Displays queued waiting message in tile subtitle and details modal', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const ep = Episode(
        id: 102,
        guid: 'ep-102',
        title: 'Queued Waiting Episode',
        mediaUrl: 'https://example.com/ep102.mp3',
        description: 'Test Desc',
        imageUrl: '',
        podcastRss: 'https://example.com/podcast.xml',
        downloadStatus: DownloadStatus.queued,
        downloadError: 'Waiting for unmetered Wi-Fi connection',
      );

      final fakeDownloadService = FakeEpisodeDownloadService();
      final fakeAudioHandler = FakeAudioHandler();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioHandlerProvider.overrideWithValue(fakeAudioHandler),
            episodeDownloadServiceProvider.overrideWithValue(fakeDownloadService),
            episodesNotifierProvider(1).overrideWith(
              (ref) => TestEpisodesNotifier([ep]),
            ),
          ],
          child: MaterialApp(
            home: EpisodeListView(podcast: testPodcast),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The subtitle and trailing button in the episode tile should display the waiting text and icon
      expect(find.text('Waiting for unmetered Wi-Fi connection'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsWidgets);

      // Tap on the episode tile to open details modal
      await tester.tap(find.text('Queued Waiting Episode'));
      await tester.pumpAndSettle();

      // In the modal, action button should show waiting status
      expect(find.text('Waiting for unmetered Wi-Fi connection • Cancel'), findsOneWidget);
    });
  });
}
