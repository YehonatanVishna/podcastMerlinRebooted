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

  /// Initializes listeners on the active [audioHandler] to keep the home screen
  /// widget in sync with current track information and playback controls.
  void init(BaseAudioHandler audioHandler) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    _playbackSub?.cancel();
    _mediaItemSub?.cancel();

    _playbackSub = audioHandler.playbackState.listen((state) {
      final oldPlaying = _lastState?.playing;
      final playingChanged = oldPlaying != state.playing;

      final now = DateTime.now();
      // Throttle continuous position updates during playback to prevent excessive IPC/battery usage
      final shouldUpdateProgress =
          state.playing && now.difference(_lastPositionUpdate).inSeconds >= 20;

      if (playingChanged || shouldUpdateProgress || _lastState == null) {
        _lastState = state;
        if (shouldUpdateProgress) {
          _lastPositionUpdate = now;
        }
        _syncWidget();
      }
    });

    _mediaItemSub = audioHandler.mediaItem.listen((item) {
      if (item?.id != _lastItem?.id ||
          item?.title != _lastItem?.title ||
          item?.artUri != _lastItem?.artUri) {
        _lastItem = item;
        _syncWidget();
      }
    });

    // Initial sync
    _lastState = audioHandler.playbackState.value;
    _lastItem = audioHandler.mediaItem.value;
    _syncWidget();
  }

  /// Syncs current metadata and playback state to HomeWidget preferences
  /// and prompts the native AppWidgetProvider to refresh.
  Future<void> _syncWidget() async {
    if (_isUpdating) return;
    _isUpdating = true;

    try {
      final state = _lastState;
      final item = _lastItem;

      final title = item?.title ?? 'Podcast Merlin';
      final podcast = item?.artist ?? item?.album ?? 'No episode playing';
      final isPlaying = state?.playing ?? false;

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
              if (file != null) {
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
    } finally {
      _isUpdating = false;
    }
  }

  /// Cancels active stream listeners.
  void dispose() {
    _playbackSub?.cancel();
    _mediaItemSub?.cancel();
    _playbackSub = null;
    _mediaItemSub = null;
  }
}
