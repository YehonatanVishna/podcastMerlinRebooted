import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/downloads/episode_download_service.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/now_playing_sheet.dart';

class FakeEpisodeDownloadService extends Fake implements EpisodeDownloadService {
  final _eventController = StreamController<DownloadTaskEvent>.broadcast();
  final Map<int, DownloadTaskEvent> _tasks = {};
  Episode? lastDownloadedEpisode;
  Episode? lastDeletedEpisode;
  int? lastCancelledId;

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
  Future<void> startDownload(Episode episode) async {
    lastDownloadedEpisode = episode;
    emitEvent(DownloadTaskEvent(
      episodeId: episode.id ?? 1,
      mediaUrl: episode.mediaUrl,
      status: DownloadStatus.downloading,
      progress: 0.25,
    ));
  }

  @override
  Future<void> deleteDownload(Episode episode) async {
    lastDeletedEpisode = episode;
    emitEvent(DownloadTaskEvent(
      episodeId: episode.id ?? 1,
      mediaUrl: episode.mediaUrl,
      status: DownloadStatus.none,
    ));
  }

  @override
  Future<void> cancelDownload(int episodeId) async {
    lastCancelledId = episodeId;
    emitEvent(DownloadTaskEvent(
      episodeId: episodeId,
      mediaUrl: '',
      status: DownloadStatus.none,
    ));
  }

  void emitEvent(DownloadTaskEvent event) {
    _eventController.add(event);
  }

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
    guid: 'guid-10',
    title: 'Episode 10',
    mediaUrl: 'https://example.com/ep10.mp3',
    description: 'Test Episode Description',
    imageUrl: '',
    podcastRss: 'https://example.com/rss.xml',
    duration: 1800,
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
    await audioHandler.playEpisode(testEpisode);
  });

  tearDown(() {
    audioHandler.stop();
    downloadService.dispose();
  });

  Widget buildTestWidget() {
    return ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
        episodeDownloadServiceProvider.overrideWithValue(downloadService),
        databaseProvider.overrideWithValue(db),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: NowPlayingSheet(),
        ),
      ),
    );
  }

  testWidgets('NowPlayingSheet renders download button in default state', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
  });

  testWidgets('Tapping download button triggers startDownload and shows SnackBar', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    final downloadBtn = find.byIcon(Icons.download_outlined);
    expect(downloadBtn, findsOneWidget);

    await tester.tap(downloadBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(downloadService.lastDownloadedEpisode?.mediaUrl, testEpisode.mediaUrl);
    expect(find.text('Starting download for "Episode 10"'), findsOneWidget);

    // After download event is emitted by startDownload, progress indicator is shown
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Receiving downloaded event updates icon to download_done_rounded', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    downloadService.emitEvent(const DownloadTaskEvent(
      episodeId: 10,
      mediaUrl: 'https://example.com/ep10.mp3',
      status: DownloadStatus.downloaded,
      downloadPath: '/data/downloads/ep10.mp3',
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);
  });

  testWidgets('Tapping downloaded button shows delete dialog and confirming deletes download', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Set episode to downloaded
    downloadService.emitEvent(const DownloadTaskEvent(
      episodeId: 10,
      mediaUrl: 'https://example.com/ep10.mp3',
      status: DownloadStatus.downloaded,
      downloadPath: '/data/downloads/ep10.mp3',
    ));
    await tester.pumpAndSettle();

    final downloadedBtn = find.byIcon(Icons.download_done_rounded);
    expect(downloadedBtn, findsOneWidget);

    // Tap downloaded button
    await tester.tap(downloadedBtn);
    await tester.pumpAndSettle();

    // Check dialog appears
    expect(find.text('Delete Download'), findsOneWidget);
    expect(find.text('Remove downloaded episode for "Episode 10" from device storage?'), findsOneWidget);

    // Tap Delete in dialog
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(downloadService.lastDeletedEpisode?.mediaUrl, testEpisode.mediaUrl);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    expect(find.text('Removed download for "Episode 10"'), findsOneWidget);
  });

  testWidgets('Tapping during downloading cancels download', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Emit downloading event
    downloadService.emitEvent(const DownloadTaskEvent(
      episodeId: 10,
      mediaUrl: 'https://example.com/ep10.mp3',
      status: DownloadStatus.downloading,
      progress: 0.5,
    ));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Tap to cancel
    await tester.tap(find.byType(IconButton).last);
    await tester.pumpAndSettle();

    expect(downloadService.lastCancelledId, 10);
    expect(find.text('Download cancelled'), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
  });
}
