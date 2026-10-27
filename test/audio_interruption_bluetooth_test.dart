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

    test('Short notification chime where begin: false arrives while pause() is still resolving', () async {
      final ep = makeTestEpisode(4, 'ep-4', 'Episode 4', 400);

      await handler.playEpisode(ep);
      expect(handler.playbackState.value.playing, isTrue);

      // Dispatch begin: true and begin: false concurrently (simulating rapid 100ms notification)
      final beginFuture = handler.handleInterruptionForTesting(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      final endFuture = handler.handleInterruptionForTesting(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );

      await Future.wait([beginFuture, endFuture]);

      // Playback must cleanly resume once the brief chime ends
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.isInterruptedForTesting, isFalse);
      expect(handler.wasPlayingBeforeInterruptionForTesting, isFalse);
    });

    test('Consecutive notification cues with settle delay do not drop resumption', () async {
      final ep = makeTestEpisode(5, 'ep-5', 'Episode 5', 500);

      await handler.playEpisode(ep);
      expect(handler.playbackState.value.playing, isTrue);

      // Cue 1 begins: audio pauses
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.isInterruptedForTesting, isTrue);
      expect(handler.wasPlayingBeforeInterruptionForTesting, isTrue);

      // Cue 1 ends: enters 250ms settle delay
      final cue1ResumeFuture = handler.handleInterruptionForTesting(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      expect(handler.isResumingFromInterruptionForTesting, isTrue);
      expect(handler.playbackState.value.playing, isFalse);

      // Cue 2 begins 50ms into settle delay: should preempt cue 1 resume and preserve state
      await Future.delayed(const Duration(milliseconds: 50));
      final cue2BeginFuture = handler.handleInterruptionForTesting(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      await cue2BeginFuture;

      expect(handler.isInterruptedForTesting, isTrue);
      expect(handler.wasPlayingBeforeInterruptionForTesting, isTrue);
      expect(handler.isResumingFromInterruptionForTesting, isFalse);
      expect(handler.playbackState.value.playing, isFalse);

      // Await cue 1's preempted resume (it will abort without playing)
      await cue1ResumeFuture;
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.wasPlayingBeforeInterruptionForTesting, isTrue);

      // Cue 2 finishes
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );

      // Playback must resume after Cue 2's settle delay
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.isInterruptedForTesting, isFalse);
      expect(handler.wasPlayingBeforeInterruptionForTesting, isFalse);
    });

    test('Ducking vs pause-and-resume actions', () async {
      final ep = makeTestEpisode(6, 'ep-6', 'Episode 6', 600);
      await handler.playEpisode(ep);
      expect(handler.playbackState.value.playing, isTrue);

      // Test Ducking mode
      handler.setAutoFocusAction(AutoFocusLossAction.duck);

      // Duck interruption: audio should keep playing at ducked volume
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(true, AudioInterruptionType.duck),
      );
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.isInterruptedForTesting, isFalse);

      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(false, AudioInterruptionType.duck),
      );
      expect(handler.playbackState.value.playing, isTrue);

      // Non-transient pause interruption while in ducking mode: must still pause
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.isInterruptedForTesting, isTrue);

      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      expect(handler.playbackState.value.playing, isTrue);

      // Test PauseAndResume mode
      handler.setAutoFocusAction(AutoFocusLossAction.pauseAndResume);

      // Duck interruption: must pause rather than duck volume
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(true, AudioInterruptionType.duck),
      );
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.isInterruptedForTesting, isTrue);

      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(false, AudioInterruptionType.duck),
      );
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.isInterruptedForTesting, isFalse);
    });

    test('User manual pause during interruption or settle delay cancels resumption [CR-03]', () async {
      final ep = makeTestEpisode(7, 'ep-7', 'Episode 7', 700);
      await handler.playEpisode(ep);
      expect(handler.playbackState.value.playing, isTrue);

      // Interruption starts
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.isInterruptedForTesting, isTrue);

      // User explicitly pauses while interrupted
      await handler.pause();
      expect(handler.wasPlayingBeforeInterruptionForTesting, isFalse);
      expect(handler.isInterruptedForTesting, isFalse);

      // Interruption ends
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );

      // Must remain paused!
      expect(handler.playbackState.value.playing, isFalse);
    });

    test('Permanent focus loss (AudioInterruptionType.unknown) does not auto-resume [CR-05]', () async {
      final ep = makeTestEpisode(8, 'ep-8', 'Episode 8', 800);
      await handler.playEpisode(ep);
      expect(handler.playbackState.value.playing, isTrue);

      // Interruption starts with unknown (permanent focus loss)
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(true, AudioInterruptionType.unknown),
      );
      expect(handler.playbackState.value.playing, isFalse);

      // Interruption ends for unknown
      await handler.handleInterruptionForTesting(
        AudioInterruptionEvent(false, AudioInterruptionType.unknown),
      );

      // Must not auto-resume on permanent focus loss
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.wasPlayingBeforeInterruptionForTesting, isFalse);
    });
  });
}
