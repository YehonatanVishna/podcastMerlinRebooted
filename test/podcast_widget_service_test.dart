import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/features/player/podcast_widget_service.dart';

class _TestAudioHandler extends BaseAudioHandler {
  void updateState(PlaybackState state) {
    playbackState.add(state);
  }

  void updateItem(MediaItem? item) {
    mediaItem.add(item);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('PodcastWidgetService Tests', () {
    test('singleton instance is non-null', () {
      final service = PodcastWidgetService.instance;
      expect(service, isNotNull);
    });

    test('exits early without setting up listeners when platform is not Android', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final service = PodcastWidgetService.instance;
      final handler = _TestAudioHandler();

      service.init(handler);
      expect(savedData, isEmpty);
      expect(updatedWidgets, isEmpty);
    });

    test('initializes and syncs initial state on Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = PodcastWidgetService.instance;
      final handler = _TestAudioHandler();

      handler.updateItem(const MediaItem(
        id: 'ep1',
        title: 'Episode One',
        artist: 'Podcast Show',
        duration: Duration(seconds: 100),
      ));
      handler.updateState(PlaybackState(
        playing: true,
        updatePosition: const Duration(seconds: 25),
      ));

      service.init(handler);
      await Future<void>.delayed(Duration.zero);

      expect(savedData['widget_title'], 'Episode One');
      expect(savedData['widget_podcast'], 'Podcast Show');
      expect(savedData['widget_is_playing'], true);
      expect(savedData['widget_progress'], 25);
      expect(updatedWidgets, contains('PodcastPlayerWidgetProvider'));
    });

    test('syncs state changes when play/pause toggles', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = PodcastWidgetService.instance;
      final handler = _TestAudioHandler();

      handler.updateItem(const MediaItem(
        id: 'ep1',
        title: 'Episode One',
        artist: 'Podcast Show',
        duration: Duration(seconds: 100),
      ));
      handler.updateState(PlaybackState(
        playing: true,
        updatePosition: const Duration(seconds: 10),
      ));

      service.init(handler);
      await Future<void>.delayed(Duration.zero);
      expect(savedData['widget_is_playing'], true);

      // Pause playback
      handler.updateState(PlaybackState(
        playing: false,
        updatePosition: const Duration(seconds: 10),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(savedData['widget_is_playing'], false);

      // Resume playback
      handler.updateState(PlaybackState(
        playing: true,
        updatePosition: const Duration(seconds: 10),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(savedData['widget_is_playing'], true);
    });

    test('immediately syncs when position jumps significantly (seek/skip)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = PodcastWidgetService.instance;
      final handler = _TestAudioHandler();

      handler.updateItem(const MediaItem(
        id: 'ep1',
        title: 'Episode One',
        artist: 'Podcast Show',
        duration: Duration(seconds: 200),
      ));
      handler.updateState(PlaybackState(
        playing: true,
        updatePosition: const Duration(seconds: 10),
      ));

      service.init(handler);
      await Future<void>.delayed(Duration.zero);
      expect(savedData['widget_progress'], 5); // 10 / 200 = 5%

      // Seek by 30 seconds (skip forward)
      handler.updateState(PlaybackState(
        playing: true,
        updatePosition: const Duration(seconds: 40),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(savedData['widget_progress'], 20); // 40 / 200 = 20%
    });

    test('syncs new media item when track changes', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = PodcastWidgetService.instance;
      final handler = _TestAudioHandler();

      service.init(handler);
      await Future<void>.delayed(Duration.zero);

      handler.updateItem(const MediaItem(
        id: 'ep2',
        title: 'Second Episode',
        album: 'Another Show',
        duration: Duration(seconds: 50),
      ));
      handler.updateState(PlaybackState(
        playing: false,
        updatePosition: const Duration(seconds: 10),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(savedData['widget_title'], 'Second Episode');
      expect(savedData['widget_podcast'], 'Another Show');
      expect(savedData['widget_progress'], 20); // 10 / 50 = 20%
    });

    test('rapid consecutive updates do not drop trailing state due to dirty flag loop', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = PodcastWidgetService.instance;
      final handler = _TestAudioHandler();

      service.init(handler);

      // Fire multiple updates synchronously without waiting between them
      handler.updateItem(const MediaItem(
        id: 'ep1',
        title: 'Initial Title',
        duration: Duration(seconds: 100),
      ));
      handler.updateState(PlaybackState(
        playing: true,
        updatePosition: const Duration(seconds: 5),
      ));
      handler.updateItem(const MediaItem(
        id: 'ep2',
        title: 'Final Title',
        artist: 'Final Artist',
        duration: Duration(seconds: 200),
      ));
      handler.updateState(PlaybackState(
        playing: false,
        updatePosition: const Duration(seconds: 50),
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Assert that the final state is what is persisted, not intermediate dropped state
      expect(savedData['widget_title'], 'Final Title');
      expect(savedData['widget_podcast'], 'Final Artist');
      expect(savedData['widget_is_playing'], false);
      expect(savedData['widget_progress'], 25); // 50 / 200 = 25%
    });

    test('handles dispose cleanly without throwing', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = PodcastWidgetService.instance;
      final handler = _TestAudioHandler();

      service.init(handler);
      expect(() => service.dispose(), returnsNormally);
    });

    test('syncs buffering state when audio enters buffering or loading state', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = PodcastWidgetService.instance;
      final handler = _TestAudioHandler();

      handler.updateItem(const MediaItem(
        id: 'ep1',
        title: 'Streaming Episode',
        artist: 'Podcast Show',
        duration: Duration(seconds: 120),
      ));
      handler.updateState(PlaybackState(
        playing: true,
        processingState: AudioProcessingState.ready,
        updatePosition: const Duration(seconds: 10),
      ));

      service.init(handler);
      await Future<void>.delayed(Duration.zero);
      expect(savedData['widget_is_buffering'], false);

      // Transitions to buffering
      handler.updateState(PlaybackState(
        playing: true,
        processingState: AudioProcessingState.buffering,
        updatePosition: const Duration(seconds: 10),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(savedData['widget_is_buffering'], true);

      // Transitions to loading
      handler.updateState(PlaybackState(
        playing: true,
        processingState: AudioProcessingState.loading,
        updatePosition: const Duration(seconds: 10),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(savedData['widget_is_buffering'], true);

      // Transitions back to ready
      handler.updateState(PlaybackState(
        playing: true,
        processingState: AudioProcessingState.ready,
        updatePosition: const Duration(seconds: 10),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(savedData['widget_is_buffering'], false);
    });

    test('syncEmpty sets widget_is_buffering to false', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = PodcastWidgetService.instance;
      final handler = _TestAudioHandler();

      handler.updateItem(const MediaItem(
        id: 'ep1',
        title: 'Streaming Episode',
        artist: 'Podcast Show',
      ));
      handler.updateState(PlaybackState(
        playing: true,
        processingState: AudioProcessingState.buffering,
      ));

      service.init(handler);
      await Future<void>.delayed(Duration.zero);
      expect(savedData['widget_is_buffering'], true);

      await service.syncEmpty();
      expect(savedData['widget_is_buffering'], false);
    });

    test('buffering state requires playing=true, sets widget_is_buffering to false when paused', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = PodcastWidgetService.instance;
      final handler = _TestAudioHandler();

      handler.updateItem(const MediaItem(
        id: 'ep1',
        title: 'Streaming Episode',
        artist: 'Podcast Show',
        duration: Duration(seconds: 120),
      ));
      handler.updateState(PlaybackState(
        playing: true,
        processingState: AudioProcessingState.buffering,
      ));

      service.init(handler);
      await Future<void>.delayed(Duration.zero);
      expect(savedData['widget_is_buffering'], true);

      // Paused while buffering
      handler.updateState(PlaybackState(
        playing: false,
        processingState: AudioProcessingState.buffering,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(savedData['widget_is_buffering'], false);
    });

    test('updateThemeColors saves primary and onPrimary colors and triggers widget update on Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = PodcastWidgetService.instance;

      const primary = Color(0xFF6750A4);
      const onPrimary = Color(0xFFFFFFFF);

      await service.updateThemeColors(primaryColor: primary, onPrimaryColor: onPrimary);

      expect(savedData['widget_color_primary'], primary.toARGB32().toSigned(32));
      expect(savedData['widget_color_on_primary'], onPrimary.toARGB32().toSigned(32));
      expect(updatedWidgets, contains('PodcastPlayerWidgetProvider'));
    });

    test('updateThemeColors is a no-op when platform is not Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final service = PodcastWidgetService.instance;

      await service.updateThemeColors(
        primaryColor: const Color(0xFF123456),
        onPrimaryColor: const Color(0xFF654321),
      );

      expect(savedData['widget_color_primary'], isNull);
      expect(savedData['widget_color_on_primary'], isNull);
      expect(updatedWidgets, isEmpty);
    });

    test('updateThemeColors skips redundant IPC if colors have not changed', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = PodcastWidgetService.instance;

      const primary = Color(0xFF6750A4);
      const onPrimary = Color(0xFFFFFFFF);

      await service.updateThemeColors(primaryColor: primary, onPrimaryColor: onPrimary);
      expect(updatedWidgets.length, 1);

      // Call again with exact same colors
      await service.updateThemeColors(primaryColor: primary, onPrimaryColor: onPrimary);
      // Count should still be 1 (no redundant save or IPC)
      expect(updatedWidgets.length, 1);
    });
  });
}
