import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/downloads/episode_download_service.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/sync/sync_service.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/episode_description_sheet.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/now_playing_sheet.dart';

class FakeSyncService extends Fake implements SyncService {
  @override
  Future<bool> pushPendingActions() async => true;
}

class FakeEpisodeDownloadService extends Fake implements EpisodeDownloadService {
  final _eventController = StreamController<DownloadTaskEvent>.broadcast();

  @override
  Stream<DownloadTaskEvent> get onDownloadEvent => _eventController.stream;

  @override
  Map<int, DownloadTaskEvent> get currentTasks => {};

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
    id: 10,
    guid: 'guid-desc-10',
    title: 'Episode 10 Auto-Dismiss Test',
    mediaUrl: 'https://example.com/ep10.mp3',
    description: 'Detailed description of episode 10',
    imageUrl: '',
    podcastRss: 'https://example.com/rss.xml',
    duration: 1800,
  );

  setUp(() async {
    db = DatabaseHelper.instance;
    final database = await db.database;
    await database.delete('active_playback');
    await database.delete('playback_queue');
    await database.delete('gpodder_actions');
    await database.delete('episodes');
    await database.delete('podcasts');

    final pod = const Podcast(
      id: 1,
      title: 'Test Podcast',
      rssUrl: 'https://example.com/rss.xml',
      link: 'https://example.com',
      description: 'Test Description',
      imageUrl: '',
    );
    await db.insertPodcast(pod);
    await db.insertEpisodes([
      testEpisode.copyWith(podcastId: 1),
      const Episode(
        id: 11,
        podcastId: 1,
        guid: 'guid-desc-11',
        title: 'Episode 11 Next',
        mediaUrl: 'https://example.com/ep11.mp3',
        description: 'Episode 11 description',
        imageUrl: '',
        podcastRss: 'https://example.com/rss.xml',
        duration: 1800,
      ),
    ]);
    final ep10 = (await db.getEpisodeByGuid('guid-desc-10'))!;

    downloadService = FakeEpisodeDownloadService();
    audioHandler = MerlinAudioHandler(
      db: db,
      syncService: FakeSyncService(),
      urlLoader: (_) async {},
    );
    await audioHandler.initFuture;
    await audioHandler.playEpisode(ep10);
  });

  tearDown(() {
    audioHandler.stop();
    downloadService.dispose();
  });

  Widget buildTestApp({Widget? child}) {
    return ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
        episodeDownloadServiceProvider.overrideWithValue(downloadService),
        databaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: child ?? const NowPlayingSheet(),
        ),
      ),
    );
  }

  testWidgets('NowPlayingSheet renders Episode Description button and opens EpisodeDescriptionSheet', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    // Verify description button icon and tooltip exist in secondary utility row
    final descBtn = find.byTooltip('Episode Description');
    expect(descBtn, findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);

    // Tap Episode Description button
    await tester.tap(descBtn);
    await tester.pumpAndSettle();

    // EpisodeDescriptionSheet should now be displayed
    expect(find.byType(EpisodeDescriptionSheet), findsOneWidget);
    expect(find.text('Episode 10 Auto-Dismiss Test'), findsWidgets);
    expect(find.textContaining('Detailed description of episode 10'), findsWidgets);
  });

  test('AudioPlayerService clears currentEpisode and emits null mediaItem when queue is empty on playback completion', () async {
    expect(audioHandler.currentEpisode, isNotNull);
    expect(audioHandler.mediaItem.value, isNotNull);
    expect(audioHandler.currentQueue, isEmpty);

    await audioHandler.onPlaybackCompletedForTesting();

    expect(audioHandler.currentEpisode, isNull);
    expect(audioHandler.mediaItem.value, isNull);
  });

  test('AudioPlayerService clears currentEpisode and emits null mediaItem on sleep timer endOfEpisode', () async {
    final nextEp = (await db.getEpisodeByGuid('guid-desc-11'))!;
    await audioHandler.addToQueue(nextEp);
    audioHandler.setSleepTimerEndOfEpisode();

    expect(audioHandler.isSleepTimerEndOfEpisode, isTrue);
    expect(audioHandler.currentQueue.length, equals(1));

    await audioHandler.onPlaybackCompletedForTesting();

    // With end of episode sleep timer, it stops and clears current episode & media item
    expect(audioHandler.currentEpisode, isNull);
    expect(audioHandler.mediaItem.value, isNull);
  });

  testWidgets('NowPlayingSheet auto-dismisses / pops when mediaItem and currentEpisode become null', (tester) async {
    await tester.pumpWidget(buildTestApp(
      child: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => NowPlayingSheet.show(context),
          child: const Text('Open NowPlaying'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Open sheet via modal bottom sheet
    await tester.tap(find.text('Open NowPlaying'));
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingSheet), findsOneWidget);

    // Simulate playback completion (queue empty)
    await tester.runAsync(() async {
      await audioHandler.onPlaybackCompletedForTesting();
      await Future.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    // NowPlayingSheet should have auto-dismissed / popped!
    expect(find.byType(NowPlayingSheet), findsNothing);
  });
}
