import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/database/database_helper.dart';
import '../../core/database/ffi_init.dart';
import '../../core/models/episode.dart';
import '../../core/models/gpodder_action.dart';
import '../../core/services/image_cache_service.dart';
import '../sync/secure_storage_service.dart';
import '../sync/sync_service.dart';
import 'linux_mpris_service.dart';
import 'podcast_widget_service.dart';

typedef PositionUpdateEvent = ({String mediaUrl, int position, bool isPlayed});
enum SleepTimerMode { none, duration, endOfEpisode }

class MerlinAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;
  final DatabaseHelper _db;
  final SyncService _syncService;
  final StreamController<PositionUpdateEvent> _positionUpdateController =
      StreamController<PositionUpdateEvent>.broadcast();

  // Queue state
  List<Episode> _queue = [];
  final StreamController<List<Episode>> _queueController =
      StreamController<List<Episode>>.broadcast();

  // Sleep timer state
  Timer? _sleepTimer;
  Duration? _sleepTimerRemaining;
  SleepTimerMode _sleepTimerMode = SleepTimerMode.none;
  final StreamController<Duration?> _sleepTimerController =
      StreamController<Duration?>.broadcast();

  // Seek durations state
  int rewindDuration = 10;
  int fastForwardDuration = 30;
  final StreamController<({int rewind, int fastForward})> _seekDurationsController =
      StreamController<({int rewind, int fastForward})>.broadcast();
  final StreamController<String> _playbackErrorController =
      StreamController<String>.broadcast();

  Stream<String> get onPlaybackError => _playbackErrorController.stream;

  Episode? _currentEpisode;
  Timer? _positionSyncTimer;
  int _lastSyncedPosition = -1;

  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription? _interruptionSub;
  StreamSubscription? _becomingNoisySub;
  bool _wasPlayingBeforeInterruption = false;
  int _playRequestId = 0;

  final Future<void> Function(String url)? urlLoader;
  double _speed = 1.0;
  Future<void>? _initFuture;
  Future<void> get initFuture => _initFuture ?? Future.value();
  Completer<void>? _preparingSourceCompleter;

  MerlinAudioHandler({
    DatabaseHelper? db,
    SyncService? syncService,
    AudioPlayer? player,
    this.urlLoader,
  })  : _db = db ?? DatabaseHelper.instance,
        _syncService = syncService ?? SyncService(),
        _player = player ?? AudioPlayer() {
    if (urlLoader == null) {
      _initAudioSession();
      _initPlayerListeners();
      LinuxMprisService.instance.init(this);
      PodcastWidgetService.instance.init(this);
    }
    _initFuture = _initService();
  }

  Future<void> _initService() async {
    await _loadInitialQueue();
    await _loadSeekDurations();
    await _restoreLastPlayback();
  }

  Future<void> _restoreLastPlayback() async {
    try {
      final activeEp = await _db.getActivePlayback();
      final isInactive = activeEp == null ||
          (activeEp.duration > 0 && activeEp.position >= (activeEp.duration - 2));

      if (isInactive) {
        if (_queue.isNotEmpty) {
          final firstQueued = _queue.first;
          _currentEpisode = firstQueued.copyWith(position: 0);
          final newItem = MediaItem(
            id: firstQueued.mediaUrl,
            album: firstQueued.podcastRss.isNotEmpty ? firstQueued.podcastRss : 'Podcast Merlin',
            artist: firstQueued.podcastRss.isNotEmpty ? firstQueued.podcastRss : 'Podcast Merlin',
            title: firstQueued.title,
            artUri: firstQueued.imageUrl.isNotEmpty ? Uri.tryParse(firstQueued.imageUrl) : null,
            duration: Duration(seconds: firstQueued.duration),
          );
          mediaItem.add(newItem);
          playbackState.add(playbackState.value.copyWith(
            controls: [
              MediaControl.rewind,
              MediaControl.play,
              MediaControl.fastForward,
              if (_queue.length > 1) MediaControl.skipToNext,
            ],
            processingState: AudioProcessingState.ready,
            playing: false,
            updatePosition: Duration.zero,
          ));
        } else {
          if (urlLoader == null) {
            PodcastWidgetService.instance.syncEmpty();
          }
        }
        return;
      }

      _currentEpisode = activeEp;

      String showTitle = 'Podcast Merlin';
      if (activeEp.podcastId != null && activeEp.podcastId! > 0) {
        final pod = await _db.getPodcastById(activeEp.podcastId!);
        if (pod != null && pod.title.isNotEmpty) {
          showTitle = pod.title;
        }
      }

      if (activeEp.imageUrl.isNotEmpty) {
        ImageCacheService.precacheImageUrl(activeEp.imageUrl);
      }

      Uri? artUri;
      if (activeEp.imageUrl.isNotEmpty) {
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
          final cachedFilePath = await ImageCacheService.getCachedFilePath(activeEp.imageUrl);
          if (cachedFilePath != null) {
            artUri = Uri.file(cachedFilePath);
          } else {
            artUri = Uri.tryParse(activeEp.imageUrl);
          }
        } else {
          artUri = Uri.tryParse(activeEp.imageUrl);
        }
      }

      final newItem = MediaItem(
        id: activeEp.mediaUrl,
        album: showTitle,
        artist: showTitle,
        title: activeEp.title,
        artUri: artUri,
        duration: Duration(seconds: activeEp.duration),
      );
      mediaItem.add(newItem);

      final restoredState = playbackState.value.copyWith(
        controls: [
          MediaControl.rewind,
          MediaControl.play,
          MediaControl.fastForward,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
          MediaAction.stop,
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.rewind,
          MediaAction.fastForward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
          MediaAction.setSpeed,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.ready,
        playing: false,
        updatePosition: Duration(seconds: activeEp.position),
        speed: _speed,
      );
      playbackState.add(restoredState);

      if (urlLoader == null) {
        LinuxMprisService.instance.updateState(restoredState, newItem);
      }
    } catch (e) {
      if (kDebugMode) print('Error restoring last playback: $e');
    }
  }

  @visibleForTesting
  Future<void> restoreLastPlaybackForTesting() => _restoreLastPlayback();

  Future<void> _prepareAudioSource(Episode ep) async {
    final localPath = ep.downloadPath;
    final bool hasLocalFile = !kIsWeb &&
        localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync();

    final targetPosition = (_currentEpisode != null && _currentEpisode!.position > 0)
        ? _currentEpisode!.position
        : ep.position;
    final initialPos = (targetPosition > 0 && !ep.isFinished && (ep.duration <= 0 || targetPosition < (ep.duration - 5)))
        ? Duration(seconds: targetPosition)
        : Duration.zero;

    if (hasLocalFile) {
      try {
        await _player.setFilePath(localPath, initialPosition: initialPos).timeout(const Duration(seconds: 30));
        return;
      } catch (e) {
        if (kDebugMode) {
          print('Failed to play local file $localPath, falling back to network stream: $e');
        }
      }
    }
    await _player.setUrl(ep.mediaUrl, initialPosition: initialPos).timeout(const Duration(seconds: 30));
  }

  Stream<PositionUpdateEvent> get onPositionUpdated => _positionUpdateController.stream;
  Episode? get currentEpisode => _currentEpisode;

  void updateEpisodeDownloadStatus({
    required int episodeId,
    required String mediaUrl,
    required DownloadStatus status,
    double progress = 0.0,
    int downloadedBytes = 0,
    int totalBytes = 0,
    String? downloadPath,
    String? error,
  }) {
    if (_currentEpisode == null) return;
    final matches = (_currentEpisode!.id != null && _currentEpisode!.id == episodeId) ||
        (_currentEpisode!.mediaUrl.isNotEmpty && _currentEpisode!.mediaUrl == mediaUrl);
    if (!matches) return;

    _currentEpisode = _currentEpisode!.copyWith(
      id: episodeId,
      downloadStatus: status,
      downloadProgress: progress,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      downloadPath: downloadPath ?? (status == DownloadStatus.none ? null : _currentEpisode!.downloadPath),
      clearDownloadPath: status == DownloadStatus.none,
      downloadError: error,
      clearDownloadError: status != DownloadStatus.failed,
    );
  }

  // Queue getters
  Stream<List<Episode>> get queueStream => _queueController.stream;
  List<Episode> get currentQueue => List.unmodifiable(_queue);
  List<Episode> get episodeQueue => List.unmodifiable(_queue);

  // Sleep timer getters
  Stream<Duration?> get sleepTimerStream => _sleepTimerController.stream;
  Duration? get sleepTimerRemaining => _sleepTimerRemaining;
  SleepTimerMode get sleepTimerMode => _sleepTimerMode;
  bool get isSleepTimerActive => _sleepTimerMode != SleepTimerMode.none;
  bool get isSleepTimerEndOfEpisode => _sleepTimerMode == SleepTimerMode.endOfEpisode;

  // Seek durations getters
  Stream<({int rewind, int fastForward})> get seekDurationsStream => _seekDurationsController.stream;
  double get speed => urlLoader != null ? _speed : _player.speed;

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());

      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(0.5);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              _wasPlayingBeforeInterruption = _player.playing;
              pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(1.0);
              break;
            case AudioInterruptionType.pause:
              if (_wasPlayingBeforeInterruption) {
                play();
              }
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        pause();
      });
    } catch (e) {
      if (kDebugMode) print('AudioSession initialization error: $e');
    }
  }

  void _initPlayerListeners() {
    _playbackEventSub = _player.playbackEventStream.listen(
      (event) {
        final playing = _player.playing;
        final newState = playbackState.value.copyWith(
          controls: [
            MediaControl.rewind,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.fastForward,
            if (_queue.isNotEmpty) MediaControl.skipToNext,
            MediaControl.stop,
          ],
          systemActions: const {
            MediaAction.play,
            MediaAction.pause,
            MediaAction.playPause,
            MediaAction.stop,
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
            MediaAction.rewind,
            MediaAction.fastForward,
            MediaAction.skipToNext,
            MediaAction.skipToPrevious,
            MediaAction.setSpeed,
          },
          androidCompactActionIndices: const [0, 1, 2],
          processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState]!,
          playing: playing,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
        );
        playbackState.add(newState);
        LinuxMprisService.instance.updateState(newState, mediaItem.value);
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) print('PlaybackEventStream error: $e');
      },
    );

    _positionSub = _player.positionStream.listen(
      (position) {
        if (_player.playing) {
          final newState = playbackState.value.copyWith(
            updatePosition: position,
            bufferedPosition: _player.bufferedPosition,
          );
          playbackState.add(newState);
          LinuxMprisService.instance.updateState(newState, mediaItem.value);
        }
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) print('PositionStream error: $e');
      },
    );

    _playerStateSub = _player.playerStateStream.listen(
      (state) {
        if (state.processingState == ProcessingState.completed) {
          _onPlaybackCompleted();
        }
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) print('PlayerStateStream error: $e');
      },
    );
  }

  Future<void> _setActiveAudioSession(bool active) async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(active);
    } catch (e) {
      if (kDebugMode) print('AudioSession setActive error: $e');
    }
  }

  @override
  Future<void> rewind() async {
    if (_initFuture != null) {
      await _initFuture;
    }
    await seekRelative(-rewindDuration);
  }

  @override
  Future<void> fastForward() async {
    if (_initFuture != null) {
      await _initFuture;
    }
    await seekRelative(fastForwardDuration);
  }

  @override
  Future<void> skipToNext() async {
    if (_initFuture != null) {
      await _initFuture;
    }
    if (_queue.isNotEmpty) {
      await playNextInQueue();
    } else {
      await fastForward();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    await rewind();
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    if (_initFuture != null) {
      await _initFuture;
    }
    switch (button) {
      case MediaButton.media:
        if (playbackState.value.playing) {
          await pause();
        } else {
          await play();
        }
        break;
      case MediaButton.next:
        await skipToNext();
        break;
      case MediaButton.previous:
        await skipToPrevious();
        break;
    }
  }

  Future<void> playEpisode(Episode episode) async {
    if (_initFuture != null) {
      await _initFuture;
    }
    if (episode.id != null) {
      await removeFromQueue(episode.id!);
    }

    if (_currentEpisode != null && _currentEpisode!.mediaUrl != episode.mediaUrl) {
      if (!_currentEpisode!.isPlayed && !_currentEpisode!.isFinished) {
        await _enqueueCurrentPositionAction();
      }
    }

    Episode epToPlay = episode;
    Episode? dbEp;
    if (epToPlay.id != null) {
      dbEp = await _db.getEpisodeById(epToPlay.id!);
    } else if (epToPlay.guid.isNotEmpty) {
      dbEp = await _db.getEpisodeByGuid(epToPlay.guid);
    } else if (epToPlay.mediaUrl.isNotEmpty) {
      dbEp = await _db.getEpisodeByMediaUrl(epToPlay.mediaUrl);
    }
    if (dbEp != null) {
      epToPlay = epToPlay.copyWith(
        id: dbEp.id,
        podcastId: epToPlay.podcastId ?? dbEp.podcastId,
        podcastRss: epToPlay.podcastRss.isNotEmpty ? epToPlay.podcastRss : dbEp.podcastRss,
        downloadPath: dbEp.downloadPath,
        downloadStatus: dbEp.downloadStatus,
        downloadProgress: dbEp.downloadProgress,
        downloadedBytes: dbEp.downloadedBytes,
      );
    }
    String showTitle = 'Podcast Merlin';
    if (epToPlay.podcastId != null && epToPlay.podcastId! > 0) {
      final pod = await _db.getPodcastById(epToPlay.podcastId!);
      if (pod != null) {
        if (pod.rssUrl.isNotEmpty) {
          epToPlay = epToPlay.copyWith(podcastRss: pod.rssUrl);
        }
        if (pod.title.isNotEmpty) {
          showTitle = pod.title;
        }
      }
    }

    final bool wasFinished = epToPlay.isFinished ||
        (epToPlay.duration > 0 && epToPlay.position >= (epToPlay.duration - 2));
    if (wasFinished) {
      epToPlay = epToPlay.copyWith(position: 0, isPlayed: false);
      await _db.updateEpisodePlaybackState(epToPlay.mediaUrl, 0, isPlayed: false);
      if (!_positionUpdateController.isClosed) {
        _positionUpdateController.add((mediaUrl: epToPlay.mediaUrl, position: 0, isPlayed: false));
      }
      if (epToPlay.podcastRss.isNotEmpty) {
        final resetAction = GPodderAction(
          podcast: epToPlay.podcastRss,
          episode: epToPlay.mediaUrl,
          guid: epToPlay.guid,
          action: 'play',
          timestamp: DateTime.now(),
          position: 0,
          started: 0,
          total: epToPlay.duration,
        );
        await _db.enqueueAction(resetAction);
        _syncService.pushPendingActions().catchError((_) => false);
      }
    }

    _currentEpisode = epToPlay;
    _lastSyncedPosition = -1; // Reset stale position marker
    await _db.saveActivePlayback(epToPlay, position: epToPlay.position, isCompleted: false);

    // Pre-cache episode artwork asynchronously
    if (epToPlay.imageUrl.isNotEmpty) {
      ImageCacheService.precacheImageUrl(epToPlay.imageUrl);
    }

    // Use local file URI for MPRIS/OS playback art if on Linux and cached; use network URL on Android/Web
    Uri? artUri;
    if (epToPlay.imageUrl.isNotEmpty) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final cachedFilePath = await ImageCacheService.getCachedFilePath(epToPlay.imageUrl);
        if (cachedFilePath != null) {
          artUri = Uri.file(cachedFilePath);
        } else {
          artUri = Uri.tryParse(epToPlay.imageUrl);
        }
      } else {
        artUri = Uri.tryParse(epToPlay.imageUrl);
      }
    }

    final newItem = MediaItem(
      id: epToPlay.mediaUrl,
      album: showTitle,
      artist: showTitle,
      title: epToPlay.title,
      artUri: artUri,
      duration: Duration(seconds: epToPlay.duration),
    );
    mediaItem.add(newItem);

    final initialLoadingState = playbackState.value.copyWith(
      controls: [
        MediaControl.rewind,
        MediaControl.pause,
        MediaControl.fastForward,
        if (_queue.isNotEmpty) MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.playPause,
        MediaAction.stop,
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.rewind,
        MediaAction.fastForward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.setSpeed,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.loading,
      playing: true,
      updatePosition: Duration(seconds: epToPlay.position),
    );
    playbackState.add(initialLoadingState);
    if (urlLoader == null) {
      LinuxMprisService.instance.updateState(initialLoadingState, newItem);
    }

    final localPath = epToPlay.downloadPath;
    final bool hasLocalFile = !kIsWeb &&
        localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync();

    if (urlLoader != null) {
      try {
        await urlLoader!(hasLocalFile ? localPath : epToPlay.mediaUrl);
      } catch (_) {}
      final readyState = initialLoadingState.copyWith(
        playing: true,
        processingState: AudioProcessingState.ready,
      );
      playbackState.add(readyState);
      _startPeriodicPositionSync();
      return;
    }

    if (audioBackendInitError != null && urlLoader == null) {
      final errorMsg = formatAudioBackendError(audioBackendInitError);
      if (kDebugMode) print(errorMsg);
      final errorState = playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      );
      playbackState.add(errorState);
      if (urlLoader == null) {
        LinuxMprisService.instance.updateState(errorState, mediaItem.value);
      }
      if (!_playbackErrorController.isClosed) {
        _playbackErrorController.add(errorMsg);
      }
      return;
    }

    final int currentRequestId = ++_playRequestId;
    try {
      await _prepareAudioSource(epToPlay);
      if (currentRequestId != _playRequestId) return;
      if (playbackState.value.playing) {
        await play();
      }
      _startPeriodicPositionSync();
    } on PlayerInterruptedException {
      // Swallowed on rapid track change
    } catch (e) {
      if (currentRequestId != _playRequestId) return;
      final errorMsg = formatAudioBackendError(e);
      if (kDebugMode) print(errorMsg);
      final errorState = playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      );
      playbackState.add(errorState);
      if (urlLoader == null) {
        LinuxMprisService.instance.updateState(errorState, mediaItem.value);
      }
      if (!_playbackErrorController.isClosed) {
        _playbackErrorController.add(errorMsg);
      }
    }
  }

  static String formatAudioBackendError(dynamic error) {
    final s = error.toString();
    if (s.contains('libmpv') || s.contains('MediaKit')) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        return 'Audio playback on Linux requires libmpv.\n'
            'Please install it using:\n'
            '  sudo dnf install mpv-libs (Fedora / RHEL)\n'
            '  sudo apt install libmpv-dev (Ubuntu / Debian)\n'
            '  sudo pacman -S mpv (Arch Linux)';
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        return 'Audio playback requires libmpv-2.dll on Windows.';
      }
    }
    return 'Playback error: $s';
  }


  @override
  Future<void> play() async {
    if (_initFuture != null) {
      await _initFuture;
    }

    if (_currentEpisode == null) {
      return;
    }

    if (_preparingSourceCompleter != null) {
      await _preparingSourceCompleter!.future;
      if (_player.playing) return;
    }

    try {
      if (urlLoader != null) {
        playbackState.add(playbackState.value.copyWith(
          playing: true,
          processingState: AudioProcessingState.ready,
        ));
        _startPeriodicPositionSync();
        return;
      }

      if (_player.audioSource == null) {
        playbackState.add(playbackState.value.copyWith(
          playing: true,
          processingState: AudioProcessingState.loading,
          controls: [MediaControl.pause, MediaControl.rewind, MediaControl.fastForward],
        ));
        final completer = Completer<void>();
        _preparingSourceCompleter = completer;
        try {
          await _prepareAudioSource(_currentEpisode!);
          completer.complete();
        } catch (e, st) {
          completer.completeError(e, st);
          rethrow;
        } finally {
          _preparingSourceCompleter = null;
        }
      }

      await _setActiveAudioSession(true);
      await _player.play();
      _startPeriodicPositionSync();
    } catch (e) {
      if (kDebugMode) print('AudioPlayerService play error: $e');
      final errorMsg = formatAudioBackendError(e);
      playbackState.add(playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      ));
      if (!_playbackErrorController.isClosed) {
        _playbackErrorController.add(errorMsg);
      }
    }
  }

  @override
  Future<void> pause() async {
    try {
      if (urlLoader != null) {
        playbackState.add(playbackState.value.copyWith(playing: false));
        _stopPeriodicPositionSync();
        await _enqueueCurrentPositionAction();
        return;
      }
      await _player.pause();
      _stopPeriodicPositionSync();
      await _enqueueCurrentPositionAction();
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      if (urlLoader != null) {
        playbackState.add(playbackState.value.copyWith(playing: false));
        _stopPeriodicPositionSync();
        await _enqueueCurrentPositionAction();
        return;
      }
      _stopPeriodicPositionSync();
      await _enqueueCurrentPositionAction();
      await _player.stop();
      await _setActiveAudioSession(false);
    } catch (_) {}
  }

  @override
  Future<void> seek(Duration position) async {
    if (_initFuture != null) {
      await _initFuture;
    }
    if (_currentEpisode == null) return;

    try {
      if (urlLoader != null) {
        _currentEpisode = _currentEpisode!.copyWith(position: position.inSeconds);
        playbackState.add(playbackState.value.copyWith(updatePosition: position));
        await _enqueueCurrentPositionAction();
        return;
      }

      if (_preparingSourceCompleter != null) {
        _currentEpisode = _currentEpisode!.copyWith(position: position.inSeconds);
        playbackState.add(playbackState.value.copyWith(updatePosition: position));
        await _preparingSourceCompleter!.future;
        await _player.seek(position);
        await _enqueueCurrentPositionAction();
        return;
      }

      if (_player.audioSource == null) {
        _currentEpisode = _currentEpisode!.copyWith(position: position.inSeconds);
        playbackState.add(playbackState.value.copyWith(updatePosition: position));
        await _db.saveActivePlayback(_currentEpisode!, position: position.inSeconds, isCompleted: false);
        await _db.updateEpisodePlaybackState(_currentEpisode!.mediaUrl, position.inSeconds, isPlayed: false);
        if (!_positionUpdateController.isClosed) {
          _positionUpdateController.add((mediaUrl: _currentEpisode!.mediaUrl, position: position.inSeconds, isPlayed: false));
        }
        if (urlLoader == null) {
          LinuxMprisService.instance.updateState(playbackState.value, mediaItem.value);
        }
        return;
      }

      await _player.seek(position);
      await _enqueueCurrentPositionAction();
    } catch (_) {}
  }

  @override
  Future<void> setSpeed(double speed) async {
    try {
      _speed = speed;
      if (urlLoader != null) {
        playbackState.add(playbackState.value.copyWith(speed: speed));
        return;
      }
      await _player.setSpeed(speed);
    } catch (_) {}
  }

  Future<void> seekRelative(int seconds) async {
    if (_initFuture != null) {
      await _initFuture;
    }
    if (_currentEpisode == null) return;

    final currentPos = (_player.audioSource != null && urlLoader == null)
        ? _player.position
        : (playbackState.value.position > Duration.zero
            ? playbackState.value.position
            : Duration(seconds: _currentEpisode!.position));
    final duration = _player.duration ?? Duration(seconds: _currentEpisode!.duration);
    final newPos = currentPos + Duration(seconds: seconds);

    if (newPos < Duration.zero) {
      await seek(Duration.zero);
    } else if (duration > Duration.zero && newPos > duration) {
      await seek(duration);
    } else {
      await seek(newPos);
    }
  }

  void _startPeriodicPositionSync() {
    if (urlLoader != null) return;
    _positionSyncTimer?.cancel();
    _positionSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _enqueueCurrentPositionAction();
    });
  }

  void _stopPeriodicPositionSync() {
    _positionSyncTimer?.cancel();
    _positionSyncTimer = null;
  }

  Future<void> _enqueueCurrentPositionAction() async {
    if (_currentEpisode == null) return;
    var podcastRss = _currentEpisode!.podcastRss;
    if (podcastRss.isEmpty && _currentEpisode!.podcastId != null && _currentEpisode!.podcastId! > 0) {
      final pod = await _db.getPodcastById(_currentEpisode!.podcastId!);
      if (pod != null) {
        podcastRss = pod.rssUrl;
        _currentEpisode = _currentEpisode!.copyWith(podcastRss: podcastRss);
      }
    }

    final currentPos = (urlLoader != null || _player.audioSource == null)
        ? playbackState.value.position
        : _player.position;
    final currentSec = currentPos.inSeconds;
    final totalSec = (_player.duration?.inSeconds ?? (mediaItem.value?.duration?.inSeconds ?? _currentEpisode!.duration));

    if (currentSec == _lastSyncedPosition) return;
    _lastSyncedPosition = currentSec;

    bool isPlayed = false;
    if (totalSec > 0 && currentSec > 0) {
      if (totalSec > 60) {
        if ((totalSec - currentSec) <= 60) {
          isPlayed = true;
        }
      } else {
        if (currentSec >= (totalSec > 10 ? totalSec - 10 : totalSec)) {
          isPlayed = true;
        }
      }
    }
    _currentEpisode = _currentEpisode!.copyWith(position: currentSec, isPlayed: isPlayed);
    await _db.updateEpisodePlaybackState(_currentEpisode!.mediaUrl, currentSec, isPlayed: isPlayed);
    await _db.saveActivePlayback(_currentEpisode!, position: currentSec, isCompleted: false);
    if (!_positionUpdateController.isClosed) {
      _positionUpdateController.add((mediaUrl: _currentEpisode!.mediaUrl, position: currentSec, isPlayed: isPlayed));
    }

    if (podcastRss.isNotEmpty) {
      final action = GPodderAction(
        podcast: podcastRss,
        episode: _currentEpisode!.mediaUrl,
        guid: _currentEpisode!.guid,
        action: 'play',
        timestamp: DateTime.now(),
        position: currentSec,
        started: 0,
        total: totalSec,
      );
      await _db.enqueueAction(action);

      // Trigger automatic background push to gPodder server
      _syncService.pushPendingActions().catchError((_) => false);
    }
  }

  Future<void> flushCurrentPlaybackPosition() async {
    await _enqueueCurrentPositionAction();
  }

  Future<void> _onPlaybackCompleted() async {
    if (_currentEpisode == null) return;
    var podcastRss = _currentEpisode!.podcastRss;
    if (podcastRss.isEmpty && _currentEpisode!.podcastId != null && _currentEpisode!.podcastId! > 0) {
      final pod = await _db.getPodcastById(_currentEpisode!.podcastId!);
      if (pod != null) {
        podcastRss = pod.rssUrl;
      }
    }

    final totalSec = (urlLoader != null
        ? _currentEpisode!.duration
        : (_player.duration?.inSeconds ?? _currentEpisode!.duration));
    _currentEpisode = _currentEpisode!.copyWith(position: totalSec, isPlayed: true);
    _lastSyncedPosition = totalSec;
    await _db.updateEpisodePlaybackState(_currentEpisode!.mediaUrl, totalSec, isPlayed: true);
    await _db.saveActivePlayback(_currentEpisode!, position: totalSec, isCompleted: true);
    if (!_positionUpdateController.isClosed) {
      _positionUpdateController.add((mediaUrl: _currentEpisode!.mediaUrl, position: totalSec, isPlayed: true));
    }

    if (podcastRss.isNotEmpty) {
      final action = GPodderAction(
        podcast: podcastRss,
        episode: _currentEpisode!.mediaUrl,
        guid: _currentEpisode!.guid,
        action: 'play',
        timestamp: DateTime.now(),
        position: totalSec,
        started: 0,
        total: totalSec,
      );
      await _db.enqueueAction(action);
      _syncService.pushPendingActions().catchError((_) => false);
    }
    _stopPeriodicPositionSync();

    // Check Sleep Timer: if endOfEpisode, stop and cancel timer!
    if (_sleepTimerMode == SleepTimerMode.endOfEpisode) {
      cancelSleepTimer();
      await pause();
      return;
    }

    // Automatically pop and play next episode if queue has items!
    if (_queue.isNotEmpty) {
      await playNextInQueue();
    } else {
      await _player.stop();
      await _setActiveAudioSession(false);
      playbackState.add(playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
        controls: [MediaControl.play],
        updatePosition: Duration.zero,
      ));
      if (urlLoader == null) {
        PodcastWidgetService.instance.syncEmpty();
      }
    }
  }

  @visibleForTesting
  Future<void> onPlaybackCompletedForTesting() => _onPlaybackCompleted();

  // --- QUEUE CONTROLS ---

  Future<void> _loadInitialQueue() async {
    try {
      _queue = await _db.getQueue();
      _syncMediaItemQueue();
    } catch (e) {
      if (kDebugMode) print('Error loading initial queue: $e');
    }
  }

  void _syncMediaItemQueue() {
    final mediaItems = _queue.map((ep) => MediaItem(
      id: ep.mediaUrl,
      album: ep.podcastRss,
      artist: ep.podcastRss,
      title: ep.title,
      duration: Duration(seconds: ep.duration),
      artUri: Uri.tryParse(ep.imageUrl),
    )).toList();
    queue.add(mediaItems);
    if (!_queueController.isClosed) {
      _queueController.add(List.unmodifiable(_queue));
    }
  }

  Future<void> addToQueue(Episode episode, {bool playNext = false}) async {
    await _db.addToQueue(episode, playNext: playNext);
    _queue = await _db.getQueue();
    _syncMediaItemQueue();
  }

  Future<void> removeFromQueue(int episodeId) async {
    await _db.removeFromQueue(episodeId);
    _queue = await _db.getQueue();
    _syncMediaItemQueue();
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    await _db.reorderQueue(oldIndex, newIndex);
    _queue = await _db.getQueue();
    _syncMediaItemQueue();
  }

  Future<void> clearQueue() async {
    await _db.clearQueue();
    _queue.clear();
    _syncMediaItemQueue();
  }

  Future<void> playNextInQueue() async {
    if (_initFuture != null) {
      await _initFuture;
    }
    if (_queue.isEmpty) return;
    final nextEpisode = _queue.first;
    if (nextEpisode.id != null) {
      await _db.removeFromQueue(nextEpisode.id!);
    }
    _queue = await _db.getQueue();
    _syncMediaItemQueue();
    await playEpisode(nextEpisode);
  }

  // --- SLEEP TIMER CONTROLS ---

  void setSleepTimer(Duration duration) {
    cancelSleepTimer();
    _sleepTimerMode = SleepTimerMode.duration;
    _sleepTimerRemaining = duration;
    if (!_sleepTimerController.isClosed) {
      _sleepTimerController.add(_sleepTimerRemaining);
    }

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_sleepTimerRemaining == null || _sleepTimerRemaining! <= const Duration(seconds: 1)) {
        timer.cancel();
        _sleepTimer = null;
        _sleepTimerRemaining = null;
        _sleepTimerMode = SleepTimerMode.none;
        if (!_sleepTimerController.isClosed) {
          _sleepTimerController.add(null);
        }
        await pause();
        if (urlLoader == null) {
          await _player.setVolume(1.0);
        }
      } else {
        _sleepTimerRemaining = _sleepTimerRemaining! - const Duration(seconds: 1);
        if (!_sleepTimerController.isClosed) {
          _sleepTimerController.add(_sleepTimerRemaining);
        }

        // Smooth volume fade out in the last 15 seconds
        if (_sleepTimerRemaining!.inSeconds <= 15) {
          final fade = (_sleepTimerRemaining!.inSeconds / 15.0).clamp(0.05, 1.0);
          if (urlLoader == null) {
            await _player.setVolume(fade);
          }
        } else if (urlLoader == null && _player.volume < 1.0) {
          await _player.setVolume(1.0);
        }
      }
    });
  }

  void setSleepTimerEndOfEpisode() {
    cancelSleepTimer();
    _sleepTimerMode = SleepTimerMode.endOfEpisode;
    _sleepTimerRemaining = null;
    if (!_sleepTimerController.isClosed) {
      _sleepTimerController.add(null);
    }
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerRemaining = null;
    _sleepTimerMode = SleepTimerMode.none;
    if (!_sleepTimerController.isClosed) {
      _sleepTimerController.add(null);
    }
    if (urlLoader == null) {
      _player.setVolume(1.0).catchError((_) {});
    }
  }

  // --- SEEK DURATIONS & SETTINGS ---

  Future<void> _loadSeekDurations() async {
    try {
      final storage = SecureStorageService();
      final rew = await storage.read(SecureStorageService.keyRewindDuration);
      final ff = await storage.read(SecureStorageService.keyFastForwardDuration);
      if (rew != null) {
        final parsed = int.tryParse(rew);
        if (parsed != null && parsed > 0) rewindDuration = parsed;
      }
      if (ff != null) {
        final parsed = int.tryParse(ff);
        if (parsed != null && parsed > 0) fastForwardDuration = parsed;
      }
      if (!_seekDurationsController.isClosed) {
        _seekDurationsController.add((rewind: rewindDuration, fastForward: fastForwardDuration));
      }
    } catch (_) {}
  }

  Future<void> setSeekDurations({int? rewind, int? fastForward}) async {
    if (rewind != null && rewind > 0) {
      rewindDuration = rewind;
      await SecureStorageService().write(SecureStorageService.keyRewindDuration, rewind.toString());
    }
    if (fastForward != null && fastForward > 0) {
      fastForwardDuration = fastForward;
      await SecureStorageService().write(SecureStorageService.keyFastForwardDuration, fastForward.toString());
    }
    if (!_seekDurationsController.isClosed) {
      _seekDurationsController.add((rewind: rewindDuration, fastForward: fastForwardDuration));
    }
  }

  void dispose() {
    PodcastWidgetService.instance.dispose();
    LinuxMprisService.instance.dispose();
    _stopPeriodicPositionSync();
    _sleepTimer?.cancel();
    _playbackEventSub?.cancel();
    _positionSub?.cancel();
    _playerStateSub?.cancel();
    _interruptionSub?.cancel();
    _becomingNoisySub?.cancel();
    _player.dispose();
    _positionUpdateController.close();
    _queueController.close();
    _sleepTimerController.close();
    _seekDurationsController.close();
    _playbackErrorController.close();
  }

}
