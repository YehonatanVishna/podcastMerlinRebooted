import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/downloads/episode_download_service.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/now_playing_sheet.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/player_dock.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeEpisodeDownloadService extends Fake implements EpisodeDownloadService {
  final _eventController = StreamController<DownloadTaskEvent>.broadcast();
  final Map<int, DownloadTaskEvent> _tasks = {};

  @override
  Stream<DownloadTaskEvent> get onDownloadEvent => _eventController.stream;

  @override
  Map<int, DownloadTaskEvent> get currentTasks => _tasks;

  @override
  bool isEpisodeActive(int episodeId) => false;

  @override
  bool isEpisodeQueued(int episodeId) => false;

  @override
  bool isEpisodePaused(int episodeId) => false;

  @override
  void dispose() {
    _eventController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;
  late MerlinAudioHandler audioHandler;
  late FakeEpisodeDownloadService downloadService;

  const testEpisode = Episode(
    id: 1,
    podcastId: 1,
    guid: 'test-ep-swipe',
    title: 'Swipe Gesture Test Episode',
    mediaUrl: 'https://example.com/audio.mp3',
    description: 'Testing swipe gestures',
    imageUrl: '',
    podcastRss: 'https://example.com/rss.xml',
    duration: 1800,
    position: 120,
  );

  setUp(() async {
    NowPlayingSheet.isShowingForTesting = false;
    db = DatabaseHelper.instance;
    final database = await db.database;
    await database.delete('gpodder_actions');
    await database.delete('episodes');
    await database.delete('podcasts');

    downloadService = FakeEpisodeDownloadService();
    audioHandler = MerlinAudioHandler(
      db: db,
      urlLoader: (_) async {},
    );
    await audioHandler.initFuture;
    await audioHandler.playEpisode(testEpisode);
  });

  tearDown(() async {
    NowPlayingSheet.isShowingForTesting = false;
    await audioHandler.stop();
    downloadService.dispose();
  });

  Widget buildTestWidget({Size size = const Size(360, 640)}) {
    return ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
        episodeDownloadServiceProvider.overrideWithValue(downloadService),
        databaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: const Scaffold(
              body: Center(child: Text('Content')),
              bottomNavigationBar: PlayerDock(),
            ),
          ),
        ),
      ),
    );
  }

  group('PlayerDock Mobile Swipe Up Tests', () {
    testWidgets('dragging upwards on compact mini player opens NowPlayingSheet', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(PlayerDock), findsOneWidget);
      expect(find.byType(NowPlayingSheet), findsNothing);

      // Drag upwards on the mini player
      await tester.drag(find.byType(PlayerDock), const Offset(0, -100));
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingSheet), findsOneWidget);
    });

    testWidgets('flinging upwards on compact mini player opens NowPlayingSheet', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingSheet), findsNothing);

      // Fling upwards with velocity
      await tester.fling(find.byType(PlayerDock), const Offset(0, -50), 1000);
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingSheet), findsOneWidget);
    });

    testWidgets('dragging downwards does not open NowPlayingSheet', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingSheet), findsNothing);

      // Drag downwards on the mini player
      await tester.drag(find.byType(PlayerDock), const Offset(0, 100));
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingSheet), findsNothing);
    });

    testWidgets('flinging downwards does not open NowPlayingSheet', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingSheet), findsNothing);

      // Fling downwards with positive velocity
      await tester.fling(find.byType(PlayerDock), const Offset(0, 80), 800);
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingSheet), findsNothing);
    });

    testWidgets('normal taps on play/pause button still toggle playback', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Initially playing
      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_filled), findsNothing);
      expect(find.byType(NowPlayingSheet), findsNothing);

      // Tap pause
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.pause_circle_filled));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      // Now paused, NowPlayingSheet not opened
      expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle_filled), findsNothing);
      expect(find.byType(NowPlayingSheet), findsNothing);

      // Tap play
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.play_circle_filled));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      // Playing again, NowPlayingSheet not opened
      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_filled), findsNothing);
      expect(find.byType(NowPlayingSheet), findsNothing);
    });

    testWidgets('normal tap on mini player body still opens NowPlayingSheet', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingSheet), findsNothing);

      // Tap on title text
      await tester.tap(find.text('Swipe Gesture Test Episode'));
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingSheet), findsOneWidget);
    });

    testWidgets('normal tap on expand button still opens NowPlayingSheet', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingSheet), findsNothing);

      // Tap on expand button
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingSheet), findsOneWidget);
    });

    testWidgets('drag starting on play/pause button opens NowPlayingSheet without triggering tap', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Initially playing
      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
      expect(find.byType(NowPlayingSheet), findsNothing);

      // Drag upwards starting on the play/pause button
      await tester.drag(find.byIcon(Icons.pause_circle_filled), const Offset(0, -100));
      await tester.pumpAndSettle();

      // Should open NowPlayingSheet
      expect(find.byType(NowPlayingSheet), findsOneWidget);
      // Playback was not paused/toggled by the drag gesture
      expect(audioHandler.playbackState.value.playing, isTrue);
    });
  });
}
