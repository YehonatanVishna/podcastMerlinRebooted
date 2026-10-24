import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Detects when the app was opened by tapping the Android home screen widget.
///
/// The native side (`MainActivity.kt`) exposes `consumeWidgetLaunch`, which returns the
/// widget launch URI once and then clears it, so that later resumes (screen unlock,
/// returning from recents) don't re-trigger the launch action.
class WidgetLaunchService {
  WidgetLaunchService._();

  static final WidgetLaunchService instance = WidgetLaunchService._();

  /// URI attached by `PodcastPlayerWidgetProvider` to request the Now Playing sheet.
  static const String nowPlayingUri = 'podcastmerlin://now-playing';

  static const MethodChannel _channel = MethodChannel('com.podcastmerlin.app/launch');

  /// Overridable for tests.
  @visibleForTesting
  Future<String?> Function()? consumeOverride;

  /// Returns the pending widget launch URI (or `null` if none) and marks it consumed.
  Future<String?> consumeWidgetLaunch() async {
    final override = consumeOverride;
    if (override != null) return override();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _channel.invokeMethod<String>('consumeWidgetLaunch');
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('WidgetLaunchService: consumeWidgetLaunch failed: $e');
      return null;
    }
  }

  /// Whether the given launch URI should open the Now Playing sheet.
  static bool shouldOpenNowPlaying(String? uri) {
    if (uri == null) return false;
    // An empty URI means a launch from an older widget instance without a URI; treat it the
    // same way since the widget only ever represents the player.
    return uri.isEmpty || uri == nowPlayingUri;
  }
}
