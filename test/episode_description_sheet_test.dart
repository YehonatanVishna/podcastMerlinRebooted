import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/sync/sync_service.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/episode_description_sheet.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/timestamped_description.dart';

class FakeSyncService extends Fake implements SyncService {
  @override
  Future<bool> pushPendingActions() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;
  late MerlinAudioHandler audioHandler;

  final testEpisode = Episode(
    id: 1,
    guid: 'test-guid-1',
    title: 'Super Exciting Episode',
    mediaUrl: 'https://example.com/audio.mp3',
    description: 'Welcome to the show! Check out chapter at 01:23 and conclusion at 12:45.',
    imageUrl: '',
    podcastRss: 'https://example.com/rss.xml',
    duration: 1800,
    publishedAt: DateTime(2026, 3, 15, 10, 30),
  );

  setUp(() async {
    db = DatabaseHelper.instance;
    final database = await db.database;
    await database.delete('active_playback');
    await database.delete('playback_queue');
    await database.delete('gpodder_actions');
    await database.delete('episodes');
    await database.delete('podcasts');

    audioHandler = MerlinAudioHandler(
      db: db,
      syncService: FakeSyncService(),
      urlLoader: (_) async {},
    );
    await audioHandler.initFuture;
  });

  tearDown(() {
    audioHandler.stop();
  });

  Widget createTestWidget({required Episode episode}) {
    return ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
        databaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => EpisodeDescriptionSheet.show(context, episode),
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('EpisodeDescriptionSheet displays title, formatted published date, and description', (tester) async {
    await tester.pumpWidget(createTestWidget(episode: testEpisode));
    await tester.pumpAndSettle();

    // Open bottom sheet
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('Super Exciting Episode'), findsOneWidget);

    // Verify Published date formatted with DateFormat.yMMMMd()
    final expectedDateStr = 'Published: ${DateFormat.yMMMMd().format(testEpisode.publishedAt!)}';
    expect(find.text(expectedDateStr), findsOneWidget);

    // Verify TimestampedDescription widget exists
    expect(find.byType(TimestampedDescription), findsOneWidget);
    expect(find.textContaining('Welcome to the show!'), findsWidgets);
    expect(find.textContaining('01:23'), findsWidgets);
  });

  testWidgets('EpisodeDescriptionSheet shows fallback text when description is empty', (tester) async {
    final emptyDescEpisode = testEpisode.copyWith(description: '   ');
    await tester.pumpWidget(createTestWidget(episode: emptyDescEpisode));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('No description available'), findsOneWidget);
  });

  testWidgets('Close button dismisses the EpisodeDescriptionSheet', (tester) async {
    await tester.pumpWidget(createTestWidget(episode: testEpisode));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();
    expect(find.byType(EpisodeDescriptionSheet), findsOneWidget);

    // Tap close button
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(EpisodeDescriptionSheet), findsNothing);
  });

  testWidgets('Tapping timestamp in description triggers seek on audioHandler', (tester) async {
    await tester.runAsync(() async {
      await audioHandler.playEpisode(testEpisode);
    });

    await tester.pumpWidget(createTestWidget(episode: testEpisode));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Find timestamp ActionChip / text for 01:23
    final timestampChip = find.text('01:23').first;
    expect(timestampChip, findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(timestampChip);
      await Future.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    // AudioHandler should seek to 1 minute 23 seconds = 83 seconds
    expect(audioHandler.playbackState.value.position.inSeconds, equals(83));
    expect(find.text('Seeking to 01:23'), findsOneWidget);
  });
}
