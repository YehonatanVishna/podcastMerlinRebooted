import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/features/player/audio_player_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeAudioPlayer extends Fake implements AudioPlayer {
  final _playbackEventSubject = StreamController<PlaybackEvent>.broadcast();
  final _positionSubject = StreamController<Duration>.broadcast();
  final _playerStateSubject = StreamController<PlayerState>.broadcast();

  bool _playing = false;
  ProcessingState _processingState = ProcessingState.idle;
  Duration _position = Duration.zero;
  final Duration _duration = const Duration(seconds: 1800);
  AudioSource? _audioSource;
  int playCallCount = 0;
  int pauseCallCount = 0;
  int setUrlCallCount = 0;
  Completer<void>? setUrlCompleter;

  @override
  Stream<PlaybackEvent> get playbackEventStream => _playbackEventSubject.stream;
  @override
  Stream<Duration> get positionStream => _positionSubject.stream;
  @override
  Stream<PlayerState> get playerStateStream => _playerStateSubject.stream;

  @override
  bool get playing => _playing;
  @override
  ProcessingState get processingState => _processingState;
  @override
  Duration get position => _position;
  @override
  Duration get bufferedPosition => _position;
  @override
  Duration? get duration => _duration;
  @override
  double get speed => 1.0;
  @override
  double get volume => 1.0;
  @override
  AudioSource? get audioSource => _audioSource;

  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    setUrlCallCount++;
    _processingState = ProcessingState.loading;
    _audioSource = AudioSource.uri(Uri.parse(url));

    // Emit event during loading where playing is false (as occurs in native just_audio on cold start)
    _playbackEventSubject.add(PlaybackEvent(
      processingState: _processingState,
      updatePosition: initialPosition ?? Duration.zero,
    ));

    if (setUrlCompleter != null) {
      await setUrlCompleter!.future;
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    _processingState = ProcessingState.ready;
    _playbackEventSubject.add(PlaybackEvent(
      processingState: _processingState,
      updatePosition: initialPosition ?? Duration.zero,
      duration: _duration,
    ));
    return _duration;
  }

  @override
  Future<Duration?> setFilePath(
    String filePath, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    return setUrl('file://$filePath', initialPosition: initialPosition, preload: preload, tag: tag);
  }

  @override
  Future<void> play() async {
    playCallCount++;
    _playing = true;
    _playbackEventSubject.add(PlaybackEvent(
      processingState: _processingState,
      updatePosition: _position,
      duration: _duration,
    ));
    _playerStateSubject.add(PlayerState(_playing, _processingState));
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
    _playing = false;
    _playbackEventSubject.add(PlaybackEvent(
      processingState: _processingState,
      updatePosition: _position,
      duration: _duration,
    ));
    _playerStateSubject.add(PlayerState(_playing, _processingState));
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _audioSource = null;
    _processingState = ProcessingState.idle;
    _playbackEventSubject.add(PlaybackEvent(
      processingState: _processingState,
      updatePosition: Duration.zero,
    ));
    _playerStateSubject.add(PlayerState(_playing, _processingState));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (position != null) {
      _position = position;
      _positionSubject.add(position);
    }
  }

  @override
  Future<void> dispose() async {
    await _playbackEventSubject.close();
    await _positionSubject.close();
    await _playerStateSubject.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;

  const ep1 = Episode(
    id: 1,
    podcastId: 1,
    guid: 'ep-1',
    title: 'Episode 1',
    mediaUrl: 'https://example.com/ep1.mp3',
    description: 'First episode',
    imageUrl: '',
    podcastRss: 'https://example.com/rss.xml',
    duration: 1800,
    position: 0,
  );

  const ep2 = Episode(
    id: 2,
    podcastId: 1,
    guid: 'ep-2',
    title: 'Episode 2',
    mediaUrl: 'https://example.com/ep2.mp3',
    description: 'Second episode',
    imageUrl: '',
    podcastRss: 'https://example.com/rss.xml',
    duration: 1800,
    position: 0,
  );

  setUp(() async {
    db = DatabaseHelper.instance;
    final database = await db.database;
    await database.delete('active_playback');
    await database.delete('playback_queue');
    await database.delete('gpodder_actions');
    await database.delete('episodes');
    await database.delete('podcasts');

    final podcast = Podcast(
      id: 1,
      rssUrl: 'https://example.com/rss.xml',
      title: 'Test Podcast',
      description: '',
      imageUrl: '',
      link: '',
      lastUpdated: DateTime.now(),
    );
    await db.insertOrUpdatePodcast(podcast);
    await db.insertEpisodes([ep1, ep2]);
  });

  group('First Play After App Startup Tests', () {
    test('playing an episode for the first time after startup automatically starts playback', () async {
      final fakePlayer = FakeAudioPlayer();
      final handler = MerlinAudioHandler(
        db: db,
        player: fakePlayer,
      );
      await handler.initFuture;
      addTearDown(handler.dispose);

      // Verify cold start state: not playing, no audio source
      expect(handler.playbackState.value.playing, isFalse);
      expect(fakePlayer.playing, isFalse);
      expect(fakePlayer.playCallCount, equals(0));

      // User clicks to play Episode 1 for the first time after startup
      await handler.playEpisode(ep1);

      // Must have invoked play() on player and handler must reflect playing == true
      expect(fakePlayer.playCallCount, equals(1), reason: 'player.play() must be called automatically on first play');
      expect(handler.playbackState.value.playing, isTrue, reason: 'playbackState must reflect playing == true');
      expect(handler.playbackState.value.processingState, equals(AudioProcessingState.ready));
      expect(handler.currentEpisode?.guid, equals('ep-1'));
    });

    test('playing episode while another episode is already paused also automatically starts playback', () async {
      final fakePlayer = FakeAudioPlayer();
      final handler = MerlinAudioHandler(
        db: db,
        player: fakePlayer,
      );
      await handler.initFuture;
      addTearDown(handler.dispose);

      // Play ep1 then pause it
      await handler.playEpisode(ep1);
      expect(handler.playbackState.value.playing, isTrue);
      await handler.pause();
      expect(handler.playbackState.value.playing, isFalse);
      expect(fakePlayer.playing, isFalse);

      // Now user clicks ep2: it must automatically start playing ep2
      await handler.playEpisode(ep2);
      expect(fakePlayer.playCallCount, equals(2));
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.currentEpisode?.guid, equals('ep-2'));
    });

    test('explicit pause during audio source loading cancels auto-play', () async {
      final fakePlayer = FakeAudioPlayer();
      final setUrlCompleter = Completer<void>();
      fakePlayer.setUrlCompleter = setUrlCompleter;

      final handler = MerlinAudioHandler(
        db: db,
        player: fakePlayer,
      );
      await handler.initFuture;
      addTearDown(handler.dispose);

      // Start playing ep1 (which waits on setUrlCompleter)
      final playFuture = handler.playEpisode(ep1);

      // Wait until setUrl is invoked and in-flight
      while (fakePlayer.setUrlCallCount == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // User cancels / pauses while it is loading
      await handler.pause();
      expect(handler.playbackState.value.playing, isFalse);

      // Now complete the loading
      setUrlCompleter.complete();
      await playFuture;

      // Since user paused during loading, play() should NOT have been invoked
      expect(fakePlayer.playCallCount, equals(0), reason: 'play() must not be called after user paused during load');
      expect(handler.playbackState.value.playing, isFalse);
    });

    test('rapid track changes only play the latest selected track', () async {
      final fakePlayer = FakeAudioPlayer();
      final handler = MerlinAudioHandler(
        db: db,
        player: fakePlayer,
      );
      await handler.initFuture;
      addTearDown(handler.dispose);

      // Rapidly initiate ep1 then ep2
      final future1 = handler.playEpisode(ep1);
      final future2 = handler.playEpisode(ep2);

      await Future.wait([future1, future2]);

      expect(handler.currentEpisode?.guid, equals('ep-2'));
      expect(handler.playbackState.value.playing, isTrue);
      expect(fakePlayer.playCallCount, equals(1));
    });
  });
}
