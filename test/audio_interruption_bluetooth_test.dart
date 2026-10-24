import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/app_settings.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Episode makeTestEpisode(int id, String guid, String title, int position) {
    return Episode(
      id: id,
      guid: guid,
      title: title,
      mediaUrl: 'https://example.com/$guid.mp3',
      description: 'Test description',
      imageUrl: '',
      podcastRss: 'https://example.com/feed.xml',
      duration: 1000,
      position: position,
    );
  }

  group('MerlinAudioHandler Interruption & In-Car Bluetooth Focus Tests', () {
    late MerlinAudioHandler handler;
    late DatabaseHelper db;

    setUp(() async {
      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('active_playback');
      await database.delete('playback_queue');
      await database.delete('gpodder_actions');
      await database.delete('episodes');
      await database.delete('podcasts');

      handler = MerlinAudioHandler(
        db: db,
        urlLoader: (_) async {},
      );
      await handler.initFuture;
    });

    tearDown(() {
      handler.dispose();
    });

    test('Initial interruption pauses playback and remembers state', () async {
      final ep = makeTestEpisode(1, 'ep-1', 'Episode 1', 100);

      await handler.playEpisode(ep);
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.isInterruptedForTesting, isFalse);

      // Trigger transient navigation interruption begin
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );

      expect(handler.isInterruptedForTesting, isTrue);
      expect(handler.wasPlayingBeforeInterruptionForTesting, isTrue);
      expect(handler.playbackState.value.playing, isFalse);
    });

    test('Rapid consecutive navigation cues do not clobber _wasPlayingBeforeInterruption', () async {
      final ep = makeTestEpisode(2, 'ep-2', 'Episode 2', 200);

      await handler.playEpisode(ep);
      expect(handler.playbackState.value.playing, isTrue);

      // Cue 1 begins: "In 500 feet, turn right"
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      expect(handler.isInterruptedForTesting, isTrue);
      expect(handler.wasPlayingBeforeInterruptionForTesting, isTrue);
      expect(handler.playbackState.value.playing, isFalse);

      // Cue 2 begins before previous state resets: "Turn right now"
      // Crucial test: should NOT overwrite wasPlayingBeforeInterruption with false!
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      expect(handler.isInterruptedForTesting, isTrue);
      expect(handler.wasPlayingBeforeInterruptionForTesting, isTrue);

      // Cue 2 finishes
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );

      expect(handler.isInterruptedForTesting, isFalse);
      expect(handler.wasPlayingBeforeInterruptionForTesting, isFalse);
      expect(handler.playbackState.value.playing, isTrue);
    });

    test('Manual pause resets _wasPlayingBeforeInterruption so interruption does not auto-resume', () async {
      final ep = makeTestEpisode(3, 'ep-3', 'Episode 3', 300);

      await handler.playEpisode(ep);
      await handler.pause();
      expect(handler.playbackState.value.playing, isFalse);

      // Interruption starts while already paused manually by user
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      expect(handler.wasPlayingBeforeInterruptionForTesting, isFalse);

      // Interruption ends
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );

      // Should remain paused!
      expect(handler.playbackState.value.playing, isFalse);
    });

    test('AutoFocusLossAction configuration defaults to pauseAndResume', () {
      expect(handler.audioFocusLossAction, equals(AutoFocusLossAction.pauseAndResume));
      handler.setAutoFocusAction(AutoFocusLossAction.duck);
      expect(handler.audioFocusLossAction, equals(AutoFocusLossAction.duck));
      handler.setAutoFocusAction(AutoFocusLossAction.pauseAndResume);
      expect(handler.audioFocusLossAction, equals(AutoFocusLossAction.pauseAndResume));
    });
  });
}
