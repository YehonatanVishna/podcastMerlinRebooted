import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/sync/sync_service.dart';
import 'package:podcast_merlin_flutter/features/sync/secure_storage_service.dart';
import 'package:podcast_merlin_flutter/features/sync/gpodder_api_client.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/ui/views/podcast_catalog_view.dart';
import 'package:podcast_merlin_flutter/features/ui/views/playback_history_view.dart';

class TestAudioHandler extends MerlinAudioHandler {
  Episode? _testEp;

  TestAudioHandler({required DatabaseHelper db}) : super(db: db, urlLoader: (_) async {});

  @override
  Episode? get currentEpisode => _testEp;

  @override
  Future<void> playEpisode(Episode episode) async {
    _testEp = episode;
  }
}

class FakeSecureStorageService extends SecureStorageService {
  final Map<String, String> _data = {};

  Future<void> saveCredentials(String server, String username, String password) async {
    _data['gpodder_server'] = server;
    _data['gpodder_username'] = username;
    _data['gpodder_password'] = password;
  }

  Future<Map<String, String?>> getCredentials() async {
    return {
      'server': _data['gpodder_server'],
      'username': _data['gpodder_username'],
      'password': _data['gpodder_password'],
    };
  }

  Future<void> clearCredentials() async {
    _data.clear();
  }

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }
}

class TestPodcastsNotifier extends StateNotifier<AsyncValue<List<Podcast>>> implements PodcastsNotifier {
  TestPodcastsNotifier(List<Podcast> podcasts) : super(AsyncValue.data(podcasts));

  @override
  Future<void> loadPodcasts() async {}

  @override
  Future<bool> addPodcastFeed(String rssUrl) async => true;

  @override
  Future<void> refreshAll({bool forceFullResync = false}) async {}

  @override
  Future<void> removePodcast(String rssUrl) async {}
}

class TestPlaybackHistoryNotifier extends StateNotifier<PlaybackHistoryState> implements PlaybackHistoryNotifier {
  TestPlaybackHistoryNotifier([List<Episode> history = const []])
      : super(PlaybackHistoryState(history: history, isLoading: false));

  @override
  Future<void> loadHistory() async {}

  @override
  Future<void> removeFromHistory(int episodeId) async {
    state = state.copyWith(
      history: state.history.where((e) => e.id != episodeId).toList(),
    );
  }

  @override
  Future<void> clearAllHistory() async {
    state = state.copyWith(history: []);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Playback History & Mark Played Database Unit Tests', () {
    late DatabaseHelper db;
    int podcastId = 1;

    setUp(() async {
      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('playback_history');
      await database.delete('gpodder_actions');
      await database.delete('episodes');
      await database.delete('podcasts');

      podcastId = await db.insertOrUpdatePodcast(
        Podcast(
          rssUrl: 'https://example.com/feed.xml',
          title: 'History & Played Test Podcast',
          description: 'A podcast for testing history and played states',
          imageUrl: 'https://example.com/art.png',
          link: 'https://example.com',
          lastUpdated: DateTime.utc(2026, 1, 1),
        ),
      );
    });

    test('recordPlaybackHistory and getPlaybackHistory upsert and retrieve history chronologically', () async {
      final ep1 = Episode(
        podcastId: podcastId,
        guid: 'ep-history-1',
        title: 'Episode 1 History',
        publishedAt: DateTime.utc(2026, 1, 1),
        mediaUrl: 'https://example.com/ep1.mp3',
        description: 'Ep 1 desc',
        imageUrl: '',
        podcastRss: 'https://example.com/feed.xml',
        duration: 1800,
        position: 900,
      );
      final ep2 = Episode(
        podcastId: podcastId,
        guid: 'ep-history-2',
        title: 'Episode 2 History',
        publishedAt: DateTime.utc(2026, 1, 2),
        mediaUrl: 'https://example.com/ep2.mp3',
        description: 'Ep 2 desc',
        imageUrl: '',
        podcastRss: 'https://example.com/feed.xml',
        duration: 2400,
        position: 2400,
      );

      await db.insertEpisodes([ep1, ep2]);
      final savedEp1 = await db.getEpisodeByGuid('ep-history-1');
      final savedEp2 = await db.getEpisodeByGuid('ep-history-2');
      expect(savedEp1, isNotNull);
      expect(savedEp2, isNotNull);

      final ep1Id = savedEp1!.id!;
      final ep2Id = savedEp2!.id!;

      final t1 = DateTime.utc(2026, 1, 10, 10, 0);
      final t2 = DateTime.utc(2026, 1, 10, 12, 0);

      await db.recordPlaybackHistory(ep1Id, playedAt: t1, position: 900, duration: 1800, completed: false);
      await db.recordPlaybackHistory(ep2Id, playedAt: t2, position: 2400, duration: 2400, completed: true);

      final history = await db.getPlaybackHistory();
      expect(history.length, 2);
      // Ordered by playedAt DESC: ep2 should be first, ep1 second
      expect(history[0].id, ep2Id);
      expect(history[0].title, 'Episode 2 History');
      expect(history[0].historyPlayedAt, t2);

      expect(history[1].id, ep1Id);
      expect(history[1].title, 'Episode 1 History');
      expect(history[1].historyPlayedAt, t1);

      // Upsert: ep1 played again later
      final t3 = DateTime.utc(2026, 1, 10, 14, 0);
      await db.recordPlaybackHistory(ep1Id, playedAt: t3, position: 1800, duration: 1800, completed: true);

      final updatedHistory = await db.getPlaybackHistory();
      expect(updatedHistory.length, 2);
      expect(updatedHistory[0].id, ep1Id);
      expect(updatedHistory[0].historyPlayedAt, t3);
    });

    test('removeEpisodeFromHistory and clearPlaybackHistory manage history table entries', () async {
      final ep1 = Episode(
        podcastId: podcastId,
        guid: 'ep-remove-1',
        title: 'Ep Remove 1',
        publishedAt: DateTime.utc(2026, 1, 1),
        mediaUrl: 'https://example.com/rem1.mp3',
        description: 'Desc 1',
        imageUrl: '',
        podcastRss: 'https://example.com/feed.xml',
        duration: 1200,
      );
      final ep2 = Episode(
        podcastId: podcastId,
        guid: 'ep-remove-2',
        title: 'Ep Remove 2',
        publishedAt: DateTime.utc(2026, 1, 2),
        mediaUrl: 'https://example.com/rem2.mp3',
        description: 'Desc 2',
        imageUrl: '',
        podcastRss: 'https://example.com/feed.xml',
        duration: 1200,
      );

      await db.insertEpisodes([ep1, ep2]);
      final saved1 = (await db.getEpisodeByGuid('ep-remove-1'))!;
      final saved2 = (await db.getEpisodeByGuid('ep-remove-2'))!;

      await db.recordPlaybackHistory(saved1.id!, position: 500, duration: 1200);
      await db.recordPlaybackHistory(saved2.id!, position: 600, duration: 1200);

      var history = await db.getPlaybackHistory();
      expect(history.length, 2);

      await db.removeEpisodeFromHistory(saved1.id!);
      history = await db.getPlaybackHistory();
      expect(history.length, 1);
      expect(history[0].id, saved2.id);

      await db.clearPlaybackHistory();
      history = await db.getPlaybackHistory();
      expect(history, isEmpty);
    });

    test('clearPlaybackHistory completely empties history even when episodes have progress or isPlayed=1', () async {
      final ep = Episode(
        podcastId: podcastId,
        guid: 'ep-played-perm',
        title: 'Played Perm',
        publishedAt: DateTime.utc(2026, 1, 1),
        mediaUrl: 'https://example.com/perm.mp3',
        description: 'Perm desc',
        imageUrl: '',
        podcastRss: 'https://example.com/feed.xml',
        duration: 2000,
        position: 1500,
        isPlayed: true,
      );
      await db.insertEpisodes([ep]);
      final saved = (await db.getEpisodeByGuid('ep-played-perm'))!;
      await db.recordPlaybackHistory(saved.id!, position: 1500, duration: 2000, completed: true);

      var history = await db.getPlaybackHistory();
      expect(history.length, 1);

      await db.clearPlaybackHistory();
      history = await db.getPlaybackHistory();
      expect(history, isEmpty);
    });

    test('setEpisodePlayed and markMultipleEpisodesPlayed toggle played status and positions in DB', () async {
      final ep1 = Episode(
        podcastId: podcastId,
        guid: 'ep-played-1',
        title: 'Ep Played 1',
        publishedAt: DateTime.utc(2026, 1, 1),
        mediaUrl: 'https://example.com/p1.mp3',
        description: 'Desc 1',
        imageUrl: '',
        podcastRss: 'https://example.com/feed.xml',
        duration: 1500,
        position: 0,
        isPlayed: false,
      );
      final ep2 = Episode(
        podcastId: podcastId,
        guid: 'ep-played-2',
        title: 'Ep Played 2',
        publishedAt: DateTime.utc(2026, 1, 2),
        mediaUrl: 'https://example.com/p2.mp3',
        description: 'Desc 2',
        imageUrl: '',
        podcastRss: 'https://example.com/feed.xml',
        duration: 2000,
        position: 0,
        isPlayed: false,
      );

      await db.insertEpisodes([ep1, ep2]);
      final id1 = (await db.getEpisodeByGuid('ep-played-1'))!.id!;
      final id2 = (await db.getEpisodeByGuid('ep-played-2'))!.id!;

      // Mark ep1 as played
      await db.setEpisodePlayed(id1, true);
      final fetched1 = await db.getEpisodeById(id1);
      expect(fetched1!.isPlayed, isTrue);
      expect(fetched1.position, 1500);

      // Reset ep1 to unplayed
      await db.setEpisodePlayed(id1, false, position: 0);
      final fetched1Reset = await db.getEpisodeById(id1);
      expect(fetched1Reset!.isPlayed, isFalse);
      expect(fetched1Reset.position, 0);

      // Bulk mark ep1 and ep2 as played
      await db.markMultipleEpisodesPlayed([id1, id2], true);
      final bulkFetched1 = await db.getEpisodeById(id1);
      final bulkFetched2 = await db.getEpisodeById(id2);
      expect(bulkFetched1!.isPlayed, isTrue);
      expect(bulkFetched1.position, 1500);
      expect(bulkFetched2!.isPlayed, isTrue);
      expect(bulkFetched2.position, 2000);

      // Bulk mark ep1 and ep2 as unplayed
      await db.markMultipleEpisodesPlayed([id1, id2], false);
      final bulkReset1 = await db.getEpisodeById(id1);
      final bulkReset2 = await db.getEpisodeById(id2);
      expect(bulkReset1!.isPlayed, isFalse);
      expect(bulkReset1.position, 0);
      expect(bulkReset2!.isPlayed, isFalse);
      expect(bulkReset2.position, 0);
    });
  });

  group('Local-Only Sync Service Unit Tests', () {
    late DatabaseHelper db;
    late FakeSecureStorageService fakeStorage;
    late SyncService syncService;

    setUp(() async {
      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('gpodder_actions');
      await database.delete('episodes');
      await database.delete('podcasts');

      fakeStorage = FakeSecureStorageService();
      syncService = SyncService(
        db: db,
        storage: fakeStorage,
        apiClient: GPodderApiClient(),
      );
    });

    test('performFullSync in local-only mode refreshes local subscriptions without gPodder server', () async {
      // Ensure no credentials in storage
      await fakeStorage.clearCredentials();

      // Insert local podcast
      await db.insertOrUpdatePodcast(
        Podcast(
          rssUrl: 'https://example.com/standalone-podcast.xml',
          title: 'Standalone Show',
          description: 'No gPodder connected',
          imageUrl: 'https://example.com/logo.png',
          link: 'https://example.com',
          lastUpdated: DateTime.utc(2026, 1, 1),
        ),
      );

      // Call performFullSync
      final success = await syncService.performFullSync();

      // Should succeed locally without errors about missing gPodder server
      expect(success, isTrue);
    });
  });

  group('PodcastCatalogView Search & Subscriptions Widget Tests', () {
    testWidgets('Tapping search icon toggles search bar and filters podcasts list in real time', (tester) async {
      final podcasts = [
        Podcast(
          id: 1,
          rssUrl: 'https://example.com/tech.xml',
          title: 'Flutter Tech Radar',
          description: 'All about Flutter and mobile engineering',
          imageUrl: '',
          link: 'https://example.com',
        ),
        Podcast(
          id: 2,
          rssUrl: 'https://example.com/history.xml',
          title: 'Ancient World Chronicles',
          description: 'In-depth historical documentaries',
          imageUrl: '',
          link: 'https://example.com',
        ),
        Podcast(
          id: 3,
          rssUrl: 'https://example.com/cooking.xml',
          title: 'Gourmet Kitchen Secrets',
          description: 'Culinary adventures and recipes',
          imageUrl: '',
          link: 'https://example.com',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            podcastsNotifierProvider.overrideWith((ref) => TestPodcastsNotifier(podcasts)),
          ],
          child: const MaterialApp(
            home: PodcastCatalogView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify all 3 podcasts initially appear
      expect(find.text('Flutter Tech Radar'), findsOneWidget);
      expect(find.text('Ancient World Chronicles'), findsOneWidget);
      expect(find.text('Gourmet Kitchen Secrets'), findsOneWidget);

      // Search bar should initially be closed
      expect(find.byType(TextField), findsNothing);

      // Tap search icon in AppBar
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      // Search TextField is now visible
      expect(find.byType(TextField), findsOneWidget);

      // Filter by title query 'radar'
      await tester.enterText(find.byType(TextField), 'radar');
      await tester.pumpAndSettle();

      expect(find.text('Flutter Tech Radar'), findsOneWidget);
      expect(find.text('Ancient World Chronicles'), findsNothing);
      expect(find.text('Gourmet Kitchen Secrets'), findsNothing);

      // Filter by description query 'historical'
      await tester.enterText(find.byType(TextField), 'historical');
      await tester.pumpAndSettle();

      expect(find.text('Flutter Tech Radar'), findsNothing);
      expect(find.text('Ancient World Chronicles'), findsOneWidget);
      expect(find.text('Gourmet Kitchen Secrets'), findsNothing);

      // Filter with no match
      await tester.enterText(find.byType(TextField), 'NonexistentQueryXYZ');
      await tester.pumpAndSettle();

      expect(find.text('No subscriptions matching "NonexistentQueryXYZ"'), findsOneWidget);

      // Tap clear search button
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      // Search is cleared, all subscriptions show again
      expect(find.text('Flutter Tech Radar'), findsOneWidget);
      expect(find.text('Ancient World Chronicles'), findsOneWidget);
      expect(find.text('Gourmet Kitchen Secrets'), findsOneWidget);

      // Close search bar
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('PlaybackHistoryView Widget Tests', () {
    testWidgets('PlaybackHistoryView renders empty state when no history exists', (tester) async {
      final db = DatabaseHelper.instance;
      final audioHandler = TestAudioHandler(db: db);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioHandlerProvider.overrideWithValue(audioHandler),
            playbackHistoryProvider.overrideWith((ref) => TestPlaybackHistoryNotifier([])),
          ],
          child: const MaterialApp(
            home: PlaybackHistoryView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No Playback History Yet'), findsOneWidget);
      expect(find.text('Episodes you play or mark as played will appear here.'), findsOneWidget);
    });

    testWidgets('PlaybackHistoryView renders history items and supports replay and clear', (tester) async {
      final db = DatabaseHelper.instance;
      final audioHandler = TestAudioHandler(db: db);
      final historyEpisode = Episode(
        id: 42,
        guid: 'hist-ep-42',
        title: 'Deep Dive Episode',
        mediaUrl: 'https://example.com/deepdive.mp3',
        podcastRss: 'https://example.com/feed.xml',
        description: 'History episode test',
        imageUrl: '',
        duration: 3600,
        position: 1800,
        historyPlayedAt: DateTime.utc(2026, 1, 15, 12, 0),
      );

      final notifier = TestPlaybackHistoryNotifier([historyEpisode]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioHandlerProvider.overrideWithValue(audioHandler),
            playbackHistoryProvider.overrideWith((ref) => notifier),
          ],
          child: const MaterialApp(
            home: PlaybackHistoryView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Deep Dive Episode'), findsOneWidget);
      expect(find.byIcon(Icons.delete_sweep_outlined), findsOneWidget);

      // Tap episode to trigger replay / playback
      await tester.tap(find.text('Deep Dive Episode'));
      await tester.pumpAndSettle();
      expect(audioHandler.currentEpisode?.title, 'Deep Dive Episode');
    });
  });
}
