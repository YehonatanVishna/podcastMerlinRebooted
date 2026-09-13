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
  });
}
