import 'dart:async';
import 'package:audio_service/audio_service.dart';
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
    guid: 'buffering-test-ep',
    title: 'Buffering Test Episode',
    mediaUrl: 'https://example.com/audio.mp3',
    description: 'Testing buffering indicator behavior',
    imageUrl: '',
    podcastRss: 'https://example.com/rss.xml',
    duration: 1800,
    position: 120,
  );

  setUp(() async {
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
    await audioHandler.stop();
    downloadService.dispose();
  });

  Widget buildPlayerDockApp({Size size = const Size(360, 640)}) {
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

  Widget buildNowPlayingSheetApp({Size size = const Size(360, 640)}) {
    return ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
        episodeDownloadServiceProvider.overrideWithValue(downloadService),
        databaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: const Scaffold(
            body: NowPlayingSheet(),
          ),
        ),
      ),
    );
  }

  group('PlayerDock Buffering UI', () {
    testWidgets('mobile mini-player reflects buffering state in progress bar, play button, and subtitle',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildPlayerDockApp(size: const Size(360, 640)));
      await tester.pumpAndSettle();

      // Initially set state to buffering
      audioHandler.playbackState.add(PlaybackState(
        playing: true,
        processingState: AudioProcessingState.buffering,
        updatePosition: const Duration(seconds: 120),
      ));
      await tester.pump();
      await tester.pump();

      // 1. LinearProgressIndicator should have null value (indeterminate)
      final progressFinder = find.byType(LinearProgressIndicator);
      expect(progressFinder, findsOneWidget);
      final progressWidget = tester.widget<LinearProgressIndicator>(progressFinder);
      expect(progressWidget.value, isNull);

      // 2. Play/Pause button should show CircularProgressIndicator spinner with tooltip 'Buffering...'
      final playPauseFinder = find.byTooltip('Buffering...');
      expect(playPauseFinder, findsOneWidget);
      expect(
        find.descendant(of: playPauseFinder, matching: find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );

      // 3. Subtitle text displays 'Buffering... • 02:00 / 30:00'
      expect(find.textContaining('Buffering... • 02:00 / 30:00'), findsOneWidget);

      // Now transition to ready state
      audioHandler.playbackState.add(PlaybackState(
        playing: true,
        processingState: AudioProcessingState.ready,
        updatePosition: const Duration(seconds: 120),
      ));
      await tester.pump();
      await tester.pump();

      // LinearProgressIndicator should have determinate value
      final readyProgressWidget = tester.widget<LinearProgressIndicator>(progressFinder);
      expect(readyProgressWidget.value, isNotNull);

      // Play/Pause button should show pause icon instead of spinner
      expect(find.byTooltip('Buffering...'), findsNothing);
      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);

      // Subtitle should no longer contain 'Buffering...'
      expect(find.textContaining('Buffering...'), findsNothing);
      expect(find.text('02:00 / 30:00'), findsOneWidget);
    });

    testWidgets('mobile mini-player also reflects AudioProcessingState.loading as buffering',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildPlayerDockApp(size: const Size(360, 640)));
      await tester.pumpAndSettle();

      audioHandler.playbackState.add(PlaybackState(
        playing: true,
        processingState: AudioProcessingState.loading,
        updatePosition: const Duration(seconds: 30),
      ));
      await tester.pump();
      await tester.pump();

      final progressWidget = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(progressWidget.value, isNull);
      expect(find.byTooltip('Buffering...'), findsOneWidget);
      expect(find.textContaining('Buffering... • 00:30 / 30:00'), findsOneWidget);
    });

    testWidgets('mobile mini-player does NOT show buffering when playing is false even if processingState is buffering',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildPlayerDockApp(size: const Size(360, 640)));
      await tester.pumpAndSettle();

      audioHandler.playbackState.add(PlaybackState(
        playing: false,
        processingState: AudioProcessingState.buffering,
        updatePosition: const Duration(seconds: 30),
      ));
      await tester.pump();
      await tester.pump();

      final progressWidget = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(progressWidget.value, isNotNull);
      expect(find.byTooltip('Buffering...'), findsNothing);
      expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
      expect(find.textContaining('Buffering...'), findsNothing);
    });

    testWidgets('desktop dock reflects buffering state in play button spinner and subtitle',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildPlayerDockApp(size: const Size(1024, 768)));
      await tester.pumpAndSettle();

      audioHandler.playbackState.add(PlaybackState(
        playing: true,
        processingState: AudioProcessingState.buffering,
        updatePosition: const Duration(seconds: 90),
      ));
      await tester.pump();
      await tester.pump();

      // Play/Pause button on desktop has tooltip 'Buffering...' and CircularProgressIndicator
      final playPauseFinder = find.byTooltip('Buffering...');
      expect(playPauseFinder, findsOneWidget);
      expect(
        find.descendant(of: playPauseFinder, matching: find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );

      // Subtitle on desktop displays 'Buffering... • 01:30 / 30:00'
      expect(find.textContaining('Buffering... • 01:30 / 30:00'), findsOneWidget);
    });
  });

  group('NowPlayingSheet Buffering UI', () {
    testWidgets('shows CircularProgressIndicator on central play button and buffering status text',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildNowPlayingSheetApp(size: const Size(360, 640)));
      await tester.pumpAndSettle();

      // Buffering state
      audioHandler.playbackState.add(PlaybackState(
        playing: true,
        processingState: AudioProcessingState.buffering,
        updatePosition: const Duration(seconds: 60),
      ));
      await tester.pump();
      await tester.pump();

      // Central play/pause button has tooltip 'Buffering...' and CircularProgressIndicator
      final playPauseFinder = find.byTooltip('Buffering...');
      expect(playPauseFinder, findsOneWidget);
      expect(
        find.descendant(of: playPauseFinder, matching: find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );

      // Status text 'Buffering audio...' is displayed
      expect(find.text('Buffering audio...'), findsOneWidget);

      // Transition to ready state
      audioHandler.playbackState.add(PlaybackState(
        playing: true,
        processingState: AudioProcessingState.ready,
        updatePosition: const Duration(seconds: 60),
      ));
      await tester.pump();
      await tester.pump();

      // Status text 'Buffering audio...' disappears
      expect(find.text('Buffering audio...'), findsNothing);

      // Central button shows normal pause icon
      expect(find.byTooltip('Buffering...'), findsNothing);
      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
    });

    testWidgets('NowPlayingSheet does NOT show buffering spinner when paused',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildNowPlayingSheetApp(size: const Size(360, 640)));
      await tester.pumpAndSettle();

      audioHandler.playbackState.add(PlaybackState(
        playing: false,
        processingState: AudioProcessingState.buffering,
        updatePosition: const Duration(seconds: 60),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byTooltip('Buffering...'), findsNothing);
      expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
      expect(find.text('Buffering audio...'), findsNothing);
    });
  });
}
