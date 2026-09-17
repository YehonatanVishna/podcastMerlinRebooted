import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import '../../core/services/image_cache_service.dart';

/// Service managing synchronization between Podcast Merlin playback state
/// and the Android home screen player widget.
class PodcastWidgetService {
  static final PodcastWidgetService instance = PodcastWidgetService._internal();

  PodcastWidgetService._internal();

  static const String _androidWidgetName = 'PodcastPlayerWidgetProvider';
  static const String _androidQualifiedName =
      'com.podcastmerlin.podcast_merlin_flutter.PodcastPlayerWidgetProvider';

  StreamSubscription<PlaybackState>? _playbackSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;

  PlaybackState? _lastState;
  MediaItem? _lastItem;
  DateTime _lastPositionUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isUpdating = false;
  bool _hasPendingUpdate = false;

  /// Initializes listeners on the active [audioHandler] to keep the home screen
  /// widget in sync with current track information and playback controls.
  void init(BaseAudioHandler audioHandler) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    _playbackSub?.cancel();
    _mediaItemSub?.cancel();

    _playbackSub = audioHandler.playbackState.listen((state) {
      final oldState = _lastState;
      final playingChanged = oldState?.playing != state.playing;
      final isBuffering = state.playing &&
          (state.processingState == AudioProcessingState.buffering ||
              state.processingState == AudioProcessingState.loading);
      final oldBuffering = (oldState?.playing ?? false) &&
          (oldState?.processingState == AudioProcessingState.buffering ||
              oldState?.processingState == AudioProcessingState.loading);
      final bufferingChanged = oldBuffering != isBuffering;

      final now = DateTime.now();
      // Throttle continuous position updates during active playback to prevent excessive IPC
      final timeSinceLastSync = now.difference(_lastPositionUpdate).inSeconds;
      final isPlayingProgressTick = state.playing && timeSinceLastSync >= 20;

      // When playing continuously, state.position advances alongside wall-clock time.
      // Detect non-linear seek/jump (e.g. widget skip forward/backward or user scrub)
      final expectedProgress = state.playing ? timeSinceLastSync : 0;
      final expectedPos = (oldState?.position.inSeconds ?? 0) + expectedProgress;
      final deviation = ((state.position.inSeconds) - expectedPos).abs();
      final positionJumped = deviation > 3;

      if (playingChanged || bufferingChanged || isPlayingProgressTick || positionJumped || _lastState == null) {
        _lastState = state;
        _lastPositionUpdate = now;
        if (_lastItem != null) {
          _triggerSync();
        }
      }
    });

    _mediaItemSub = audioHandler.mediaItem.listen((item) {
      if (item != _lastItem) {
        final wasNull = _lastItem == null;
        _lastItem = item;
        if (item != null || !wasNull) {
          _triggerSync();
        }
      }
    });

    // Initial sync - only sync if active media item is present to prevent wiping widget data on cold start
    _lastState = audioHandler.playbackState.value;
    _lastItem = audioHandler.mediaItem.value;
    if (_lastItem != null) {
      _triggerSync();
    }
  }

  /// Explicitly reset widget data to empty state when playback is cleared or finishes
  Future<void> syncEmpty() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      _lastItem = null;
      await Future.wait([
        HomeWidget.saveWidgetData<String>('widget_title', 'Podcast Merlin'),
        HomeWidget.saveWidgetData<String>('widget_podcast', 'No episode playing'),
        HomeWidget.saveWidgetData<bool>('widget_is_playing', false),
        HomeWidget.saveWidgetData<bool>('widget_is_buffering', false),
        HomeWidget.saveWidgetData<int>('widget_progress', 0),
        HomeWidget.saveWidgetData<String?>('widget_artwork_path', null),
      ]);
      await HomeWidget.updateWidget(
        name: _androidWidgetName,
        qualifiedAndroidName: _androidQualifiedName,
      );
    } catch (e) {
      if (kDebugMode) {
        print('PodcastWidgetService syncEmpty error: $e');
      }
    }
  }

  /// Triggers a widget synchronization, re-queuing if an update is already in-flight.
  void _triggerSync() {
    if (_isUpdating) {
      _hasPendingUpdate = true;
      return;
    }
    _syncWidget();
  }

  /// Syncs current metadata and playback state to HomeWidget preferences
  /// and prompts the native AppWidgetProvider to refresh.
  Future<void> _syncWidget() async {
    _isUpdating = true;

    try {
      do {
        _hasPendingUpdate = false;
        await _performSync();
      } while (_hasPendingUpdate);
    } finally {
      _isUpdating = false;
    }
  }

  Future<void> _performSync() async {
    try {
      final state = _lastState;
      final item = _lastItem;

      final title = item?.title ?? 'Podcast Merlin';
      final podcast = item?.artist ?? item?.album ?? 'No episode playing';
      final isPlaying = state?.playing ?? false;
      final isBuffering = isPlaying &&
          (state?.processingState == AudioProcessingState.buffering ||
              state?.processingState == AudioProcessingState.loading);

      final positionSec = state?.position.inSeconds ?? 0;
      final durationSec = item?.duration?.inSeconds ?? 0;
      final progress = durationSec > 0
          ? ((positionSec / durationSec) * 100).clamp(0, 100).toInt()
          : 0;

      String? artworkPath;
      final artUri = item?.artUri;
      if (artUri != null) {
        if (artUri.isScheme('file')) {
          artworkPath = artUri.toFilePath();
        } else {
          final url = artUri.toString();
          artworkPath = await ImageCacheService.getCachedFilePath(url);
          if (artworkPath == null && url.startsWith('http')) {
            // Trigger background download and cache so subsequent widget update displays it
            unawaited(ImageCacheService.downloadAndCache(url).then((file) {
              if (file != null && _lastItem?.artUri?.toString() == url) {
                HomeWidget.saveWidgetData<String>('widget_artwork_path', file.path);
                HomeWidget.updateWidget(
                  name: _androidWidgetName,
                  qualifiedAndroidName: _androidQualifiedName,
                );
              }
            }));
          }
        }
      }

      await Future.wait([
        HomeWidget.saveWidgetData<String>('widget_title', title),
        HomeWidget.saveWidgetData<String>('widget_podcast', podcast),
        HomeWidget.saveWidgetData<bool>('widget_is_playing', isPlaying),
        HomeWidget.saveWidgetData<bool>('widget_is_buffering', isBuffering),
        HomeWidget.saveWidgetData<int>('widget_progress', progress),
        HomeWidget.saveWidgetData<String?>('widget_artwork_path', artworkPath),
      ]);

      await HomeWidget.updateWidget(
        name: _androidWidgetName,
        qualifiedAndroidName: _androidQualifiedName,
      );
    } catch (e) {
      if (kDebugMode) {
        print('PodcastWidgetService sync error: $e');
      }
    }
  }

  /// Cancels active stream listeners.
  void dispose() {
    _playbackSub?.cancel();
    _mediaItemSub?.cancel();
    _playbackSub = null;
    _mediaItemSub = null;
    _lastState = null;
    _lastItem = null;
    _isUpdating = false;
    _hasPendingUpdate = false;
  }
}
