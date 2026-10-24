import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Brightness, Color, ColorScheme;
import 'package:home_widget/home_widget.dart';
import '../../core/models/app_settings.dart';
import '../../core/services/image_cache_service.dart';
import '../../core/theme/app_theme.dart';

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
  int? _lastPrimaryColor;
  int? _lastOnPrimaryColor;
  int? _lastSurfaceColor;
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

  Future<void> _updateWidget() => HomeWidget.updateWidget(
        name: _androidWidgetName,
        qualifiedAndroidName: _androidQualifiedName,
      );

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
      await _updateWidget();
    } catch (e) {
      if (kDebugMode) {
        print('PodcastWidgetService syncEmpty error: $e');
      }
    }
  }

  /// Updates the home screen widget theme colors based on the app's active color scheme.
  /// Computes the widget's theme colors from [settings], mirroring the dark theme built
  /// in `PodcastMerlinApp`.
  ///
  /// [dynamicDark] is the (un-harmonized) dark Material You scheme; it is ignored unless
  /// `settings.useDynamicColor` is enabled. The surface color is `null` whenever dynamic
  /// colors or AMOLED mode are active so Android 12+ natively applies the
  /// `system_accent2_800` wallpaper-tinted background (matching e.g. the YouTube widget)
  /// instead of a flat dark grey/black surface.
  static ({Color primary, Color onPrimary, Color? surface}) resolveWidgetColors(
    AppSettings settings, {
    ColorScheme? dynamicDark,
  }) {
    final useDynamic = settings.useDynamicColor;
    final isAmoled = settings.themeMode == AppThemeMode.amoled;
    final scheme = useDynamic ? dynamicDark : null;
    final seed = settings.accentColor.color;
    final darkTheme = isAmoled
        ? AppTheme.createAmoledTheme(scheme, seedColor: seed)
        : AppTheme.createDarkTheme(scheme, seedColor: seed);
    return (
      primary: darkTheme.colorScheme.primary,
      onPrimary: darkTheme.colorScheme.onPrimary,
      surface: (useDynamic || isAmoled) ? null : darkTheme.colorScheme.surfaceContainer,
    );
  }

  /// Resolves the platform's dark Material You scheme the same way `DynamicColorBuilder`
  /// does. Works headlessly (no Activity), e.g. when playback was started from the widget
  /// and AudioService spun up the Flutter engine in the background.
  @visibleForTesting
  Future<ColorScheme?> Function() dynamicDarkResolver = _resolveDynamicDark;

  static Future<ColorScheme?> _resolveDynamicDark() async {
    try {
      final corePalette = await DynamicColorPlugin.getCorePalette();
      if (corePalette != null) {
        return corePalette.toColorScheme(brightness: Brightness.dark);
      }
    } catch (_) {}
    try {
      final accent = await DynamicColorPlugin.getAccentColor();
      if (accent != null) {
        return ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark);
      }
    } catch (_) {}
    return null;
  }

  int _themeSyncGeneration = 0;

  /// Pushes the widget theme colors derived from [settings] without depending on the
  /// widget tree being built. The UI tree doesn't render frames while the engine runs
  /// headlessly, so relying solely on post-frame callbacks left the widget with the
  /// default purple theme until the app was opened.
  Future<void> syncThemeWithSettings(AppSettings settings, {ColorScheme? dynamicDark}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final generation = ++_themeSyncGeneration;
    var scheme = dynamicDark;
    if (settings.useDynamicColor && scheme == null) {
      scheme = await dynamicDarkResolver();
      // A newer sync was requested while resolving; let it win.
      if (generation != _themeSyncGeneration) return;
    }
    final colors = resolveWidgetColors(settings, dynamicDark: scheme);
    await updateThemeColors(
      primaryColor: colors.primary,
      onPrimaryColor: colors.onPrimary,
      surfaceColor: colors.surface,
    );
  }

  Future<void> updateThemeColors({
    required Color primaryColor,
    required Color onPrimaryColor,
    Color? surfaceColor,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final pVal = primaryColor.toARGB32().toSigned(32);
    final opVal = onPrimaryColor.toARGB32().toSigned(32);
    final sVal = surfaceColor?.toARGB32().toSigned(32);

    if (_lastPrimaryColor == pVal &&
        _lastOnPrimaryColor == opVal &&
        _lastSurfaceColor == sVal) {
      return;
    }

    _lastPrimaryColor = pVal;
    _lastOnPrimaryColor = opVal;
    _lastSurfaceColor = sVal;

    try {
      final futures = <Future>[
        HomeWidget.saveWidgetData<int>('widget_color_primary', pVal),
        HomeWidget.saveWidgetData<int>('widget_color_on_primary', opVal),
        HomeWidget.saveWidgetData<int?>('widget_color_surface', sVal),
      ];
      await Future.wait(futures);
      await _updateWidget();
    } catch (e) {
      _lastPrimaryColor = null;
      _lastOnPrimaryColor = null;
      _lastSurfaceColor = null;
      if (kDebugMode) {
        print('PodcastWidgetService updateThemeColors error: $e');
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
            unawaited(ImageCacheService.downloadAndCache(url).then((file) async {
              if (file != null && _lastItem?.artUri?.toString() == url) {
                await HomeWidget.saveWidgetData<String>('widget_artwork_path', file.path);
                await _updateWidget();
              }
            }).catchError((e) {
              if (kDebugMode) {
                print('PodcastWidgetService artwork background download error: $e');
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

      await _updateWidget();
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
    _lastPrimaryColor = null;
    _lastOnPrimaryColor = null;
    _lastSurfaceColor = null;
    _isUpdating = false;
    _hasPendingUpdate = false;
  }
}
