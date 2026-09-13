import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:podcast_merlin_flutter/features/player/podcast_widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;

  setUp(() async {
    db = DatabaseHelper.instance;
    final database = await db.database;
    await database.delete('active_playback');
    await database.delete('playback_queue');
    await database.delete('gpodder_actions');
    await database.delete('episodes');
    await database.delete('podcasts');
  });

  group('DatabaseHelper Active Playback Persistence Tests', () {
    test('saveActivePlayback and getActivePlayback persist and restore episode state', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/show.xml',
        title: 'Show Title',
        description: 'Show Desc',
        imageUrl: 'https://example.com/art.jpg',
        link: 'https://example.com',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final episode = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/show.xml',
        guid: 'active-ep-1',
        title: 'Active Episode 1',
        description: 'Active Desc',
        mediaUrl: 'https://example.com/ep1.mp3',
        duration: 3600,
        position: 1200,
        imageUrl: 'https://example.com/ep1.jpg',
      );
      await db.insertEpisodes([episode]);
      final savedEp = await db.getEpisodeByGuid('active-ep-1');
      expect(savedEp, isNotNull);

      // Save as active playback
      await db.saveActivePlayback(savedEp!, position: 1250, isCompleted: false);

      final restored = await db.getActivePlayback();
      expect(restored, isNotNull);
      expect(restored!.title, equals('Active Episode 1'));
      expect(restored.mediaUrl, equals('https://example.com/ep1.mp3'));
      expect(restored.position, equals(1250));
      expect(restored.duration, equals(3600));
    });

    test('getActivePlayback returns null when playback was completed', () async {
      final episode = Episode(
        podcastRss: 'https://example.com/rss.xml',
        guid: 'active-ep-completed',
        title: 'Completed Episode',
        description: '',
        mediaUrl: 'https://example.com/ep_done.mp3',
        duration: 1000,
        position: 1000,
        imageUrl: '',
      );

      await db.saveActivePlayback(episode, position: 1000, isCompleted: true);

      final active = await db.getActivePlayback(includeCompleted: false);
      expect(active, isNull);

      final completed = await db.getActivePlayback(includeCompleted: true);
      expect(completed, isNotNull);
      expect(completed!.title, equals('Completed Episode'));
    });

    test('clearActivePlayback deletes active playback row', () async {
      final episode = Episode(
        podcastRss: 'https://example.com/rss.xml',
        guid: 'ep-to-clear',
        title: 'To Clear',
        description: '',
        mediaUrl: 'https://example.com/clear.mp3',
        duration: 500,
        position: 100,
        imageUrl: '',
      );

      await db.saveActivePlayback(episode, position: 100, isCompleted: false);
      expect(await db.getActivePlayback(), isNotNull);

      await db.clearActivePlayback();
      expect(await db.getActivePlayback(), isNull);
    });
  });

  group('MerlinAudioHandler Active Playback & Queue Restoration Tests', () {
    test('cold start restores active playback and play queue from database', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/feed.xml',
        title: 'Podcast Show',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final activeEp = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/feed.xml',
        guid: 'active-ep',
        title: 'Active Now Episode',
        description: '',
        mediaUrl: 'https://example.com/active.mp3',
        duration: 2000,
        position: 450,
        imageUrl: '',
      );
      final queueEp1 = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/feed.xml',
        guid: 'q-1',
        title: 'Queue Item 1',
        description: '',
        mediaUrl: 'https://example.com/q1.mp3',
        duration: 1500,
        position: 0,
        imageUrl: '',
      );
      final queueEp2 = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/feed.xml',
        guid: 'q-2',
        title: 'Queue Item 2',
        description: '',
        mediaUrl: 'https://example.com/q2.mp3',
        duration: 1800,
        position: 0,
        imageUrl: '',
      );

      await db.insertEpisodes([activeEp, queueEp1, queueEp2]);
      final savedActive = (await db.getEpisodeByGuid('active-ep'))!;
      final savedQ1 = (await db.getEpisodeByGuid('q-1'))!;
      final savedQ2 = (await db.getEpisodeByGuid('q-2'))!;

      await db.saveActivePlayback(savedActive, position: 450, isCompleted: false);
      await db.addToQueue(savedQ1);
      await db.addToQueue(savedQ2);

      // Simulate app starting up after being closed for hours
      final loadedUrls = <String>[];
      final handler = MerlinAudioHandler(
        db: db,
        urlLoader: (url) async => loadedUrls.add(url),
      );
      await handler.initFuture;
      addTearDown(handler.dispose);

      // Verify active episode was restored in paused/ready state
      expect(handler.currentEpisode, isNotNull);
      expect(handler.currentEpisode!.guid, equals('active-ep'));
      expect(handler.currentEpisode!.position, equals(450));
      expect(handler.mediaItem.value?.title, equals('Active Now Episode'));
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.position.inSeconds, equals(450));

      // Verify queue was restored
      expect(handler.currentQueue.length, equals(2));
      expect(handler.currentQueue[0].guid, equals('q-1'));
      expect(handler.currentQueue[1].guid, equals('q-2'));

      // Resuming playback via play() (e.g. user taps play in mini player or widget)
      await handler.play();
      expect(handler.playbackState.value.playing, isTrue);

      // Fast-forward seek while active
      await handler.fastForward();
      expect(handler.playbackState.value.position.inSeconds, greaterThan(450));

      // Pause and flush
      await handler.pause();
      expect(handler.playbackState.value.playing, isFalse);

      final updatedInDb = await db.getActivePlayback();
      expect(updatedInDb, isNotNull);
      expect(updatedInDb!.position, equals(handler.playbackState.value.position.inSeconds));
    });

    test('click on widget media button resumes restored playback', () async {
      final activeEp = Episode(
        podcastRss: 'https://example.com/rss.xml',
        guid: 'widget-ep',
        title: 'Widget Resume Episode',
        description: '',
        mediaUrl: 'https://example.com/widget.mp3',
        duration: 3000,
        position: 900,
        imageUrl: '',
      );
      await db.saveActivePlayback(activeEp, position: 900, isCompleted: false);

      final handler = MerlinAudioHandler(
        db: db,
        urlLoader: (_) async {},
      );
      addTearDown(handler.dispose);

      // Simulate widget click (KEYCODE_MEDIA_PLAY_PAUSE dispatching click(MediaButton.media))
      await handler.click(MediaButton.media);

      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.currentEpisode?.guid, equals('widget-ep'));
    });

    test('play does nothing if no episode is actively playing', () async {
      // Database has no active playback
      final handler = MerlinAudioHandler(
        db: db,
        urlLoader: (_) async {},
      );
      await handler.initFuture;
      addTearDown(handler.dispose);

      expect(handler.currentEpisode, isNull);
      expect(handler.mediaItem.value, isNull);

      // User clicks play on widget when nothing is active
      await handler.click(MediaButton.media);

      // Playback must not start
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.currentEpisode, isNull);
    });

    test('playback completion advances queue and updates active playback', () async {
      final podcast = Podcast(
        rssUrl: 'https://example.com/advance.xml',
        title: 'Advance Show',
        description: '',
        imageUrl: '',
        link: '',
        lastUpdated: DateTime.now(),
      );
      final podId = await db.insertOrUpdatePodcast(podcast);

      final ep1 = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/advance.xml',
        guid: 'adv-1',
        title: 'Advance Episode 1',
        description: '',
        mediaUrl: 'https://example.com/adv1.mp3',
        duration: 100,
        position: 0,
        imageUrl: '',
      );
      final ep2 = Episode(
        podcastId: podId,
        podcastRss: 'https://example.com/advance.xml',
        guid: 'adv-2',
        title: 'Advance Episode 2',
        description: '',
        mediaUrl: 'https://example.com/adv2.mp3',
        duration: 200,
        position: 0,
        imageUrl: '',
      );
      await db.insertEpisodes([ep1, ep2]);
      final s1 = (await db.getEpisodeByGuid('adv-1'))!;
      final s2 = (await db.getEpisodeByGuid('adv-2'))!;

      final handler = MerlinAudioHandler(
        db: db,
        urlLoader: (_) async {},
      );
      await handler.initFuture;
      addTearDown(handler.dispose);

      await handler.addToQueue(s2);
      await handler.playEpisode(s1);

      expect(handler.currentEpisode?.guid, equals('adv-1'));
      expect(handler.currentQueue.length, equals(1));

      // Simulate playback completion of ep1
      await handler.onPlaybackCompletedForTesting();

      // ep2 should now be current and popped from queue
      expect(handler.currentEpisode?.guid, equals('adv-2'));
      expect(handler.currentQueue, isEmpty);

      // active_playback in DB should now be ep2
      final activeInDb = await db.getActivePlayback();
      expect(activeInDb, isNotNull);
      expect(activeInDb!.guid, equals('adv-2'));
    });
  });

  group('PodcastWidgetService Cold Start & Sync Tests', () {
    final savedData = <String, dynamic>{};
    final updatedWidgets = <String>[];

    setUp(() {
      savedData.clear();
      updatedWidgets.clear();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'), (call) async {
        if (call.method == 'saveWidgetData') {
          final args = call.arguments as Map;
          savedData[args['id'] as String] = args['data'];
          return true;
        } else if (call.method == 'updateWidget') {
          final args = call.arguments as Map;
          updatedWidgets.add(args['name'] as String? ?? 'unknown');
          return true;
        }
        return null;
      });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      PodcastWidgetService.instance.dispose();
    });

    test('does not overwrite widget data on Android cold start when mediaItem is initially null', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = PodcastWidgetService.instance;

      // Simulate existing widget state in preferences from before app closed
      savedData['widget_title'] = 'Previous Episode Title';
      savedData['widget_podcast'] = 'Previous Podcast Show';
      savedData['widget_is_playing'] = false;
      savedData['widget_progress'] = 50;

      final handler = MerlinAudioHandler(
        db: db,
        urlLoader: (_) async {},
      );
      addTearDown(handler.dispose);

      service.init(handler);
      await Future<void>.delayed(Duration.zero);

      // Widget data should NOT have been wiped to "No episode playing"
      expect(savedData['widget_title'], equals('Previous Episode Title'));
      expect(savedData['widget_podcast'], equals('Previous Podcast Show'));
      expect(savedData['widget_progress'], equals(50));
    });

    test('syncs restored episode when media item is restored into handler', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = PodcastWidgetService.instance;

      final activeEp = Episode(
        guid: 'sync-restored',
        title: 'Restored Show Title',
        podcastRss: 'Great Podcast',
        description: '',
        mediaUrl: 'https://example.com/restored.mp3',
        duration: 1000,
        position: 400,
        imageUrl: '',
      );
      await db.saveActivePlayback(activeEp, position: 400, isCompleted: false);

      final handler = MerlinAudioHandler(
        db: db,
        urlLoader: (_) async {},
      );
      await handler.initFuture;
      addTearDown(handler.dispose);

      service.init(handler);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(savedData['widget_title'], equals('Restored Show Title'));
      expect(savedData['widget_is_playing'], isFalse);
      expect(savedData['widget_progress'], equals(40)); // 400 / 1000 = 40%
    });

    test('position sync with less than 60 seconds remaining preserves active playback session for restoration (CRIT-2)', () async {
      final episode = Episode(
        guid: 'near-end-ep',
        title: 'Near End Episode',
        podcastRss: 'https://example.com/podcast.xml',
        description: '',
        mediaUrl: 'https://example.com/near_end.mp3',
        duration: 1800,
        position: 1750, // 50 seconds remaining (< 60s)
        imageUrl: '',
      );
      await db.insertEpisodes([episode]);

      final handler = MerlinAudioHandler(
        db: db,
        urlLoader: (_) async {},
      );
      addTearDown(handler.dispose);
      await handler.initFuture;

      await handler.playEpisode(episode);
      // Seek to 1755s (45s left)
      await handler.seek(const Duration(seconds: 1755));
      await handler.flushCurrentPlaybackPosition();

      // Ensure that in the database, active_playback still has isCompleted = 0
      final active = await db.getActivePlayback(includeCompleted: false);
      expect(active, isNotNull, reason: 'Session must NOT be completed just because < 60s remain');
      expect(active!.position, equals(1755));

      // Simulate cold start in a fresh handler
      final coldStartHandler = MerlinAudioHandler(
        db: db,
        urlLoader: (_) async {},
      );
      addTearDown(coldStartHandler.dispose);
      await coldStartHandler.initFuture;

      expect(coldStartHandler.currentEpisode, isNotNull);
      expect(coldStartHandler.currentEpisode!.guid, equals('near-end-ep'));
      expect(coldStartHandler.currentEpisode!.position, equals(1755));
      expect(coldStartHandler.playbackState.value.position.inSeconds, equals(1755));
    });

    test('cold start with completed active playback falls back to first queued episode (MED-1)', () async {
      // Completed episode in active_playback
      final finishedEp = Episode(
        guid: 'finished-ep',
        title: 'Finished Episode',
        podcastRss: 'https://example.com/podcast.xml',
        description: '',
        mediaUrl: 'https://example.com/finished.mp3',
        duration: 1800,
        position: 1800,
        imageUrl: '',
      );
      await db.saveActivePlayback(finishedEp, position: 1800, isCompleted: true);

      // Queued episode waiting to be played
      final queuedEp = Episode(
        guid: 'next-queued-ep',
        title: 'Next Queued Episode',
        podcastRss: 'https://example.com/podcast.xml',
        description: '',
        mediaUrl: 'https://example.com/next_queued.mp3',
        duration: 2400,
        position: 0,
        imageUrl: '',
      );
      await db.addToQueue(queuedEp);

      // Cold start
      final handler = MerlinAudioHandler(
        db: db,
        urlLoader: (_) async {},
      );
      addTearDown(handler.dispose);
      await handler.initFuture;

      // Should have restored next-queued-ep as currentEpisode
      expect(handler.currentEpisode, isNotNull);
      expect(handler.currentEpisode!.guid, equals('next-queued-ep'));
      expect(handler.currentEpisode!.title, equals('Next Queued Episode'));
      expect(handler.mediaItem.value?.title, equals('Next Queued Episode'));
      expect(handler.playbackState.value.playing, isFalse);
    });
  });
}
