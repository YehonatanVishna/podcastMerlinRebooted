import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/features/player/podcast_widget_service.dart';

class _FakeAudioHandler extends BaseAudioHandler {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PodcastWidgetService Tests', () {
    test('singleton instance is non-null', () {
      final service = PodcastWidgetService.instance;
      expect(service, isNotNull);
    });

    test('init and dispose complete cleanly without exceptions', () {
      final service = PodcastWidgetService.instance;
      final fakeHandler = _FakeAudioHandler();

      expect(() => service.init(fakeHandler), returnsNormally);
      expect(() => service.dispose(), returnsNormally);
    });
  });
}
