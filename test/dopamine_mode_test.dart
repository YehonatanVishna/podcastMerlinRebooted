import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/dopamine_switcher_sheet.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/dopamine_tunnel_canvas.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/dopamine_video_canvas.dart';

class MockDopamineVideoCanvasController implements DopamineVideoCanvasController {
  bool _isPlaying = false;
  bool disposed = false;

  @override
  bool get isInitialized => true;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Future<void> play() async {
    _isPlaying = true;
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dopamine Mode Models & Serialization', () {
    test('DopamineVisualType exposes correct labels', () {
      expect(DopamineVisualType.proceduralTunnel.label, 'Neon Warp Tunnel');
      expect(DopamineVisualType.customVideo.label, 'Custom Video');
    });

    test('DopamineCustomVideo roundtrip JSON serialization', () {
      final video = DopamineCustomVideo(
        id: '12345',
        name: 'My Clips',
        path: '/path/to/my_clips.mp4',
        sizeBytes: 1048576,
        addedAt: DateTime(2026, 1, 1),
      );

      final json = video.toJson();
      expect(json['id'], '12345');
      expect(json['name'], 'My Clips');
      expect(json['path'], '/path/to/my_clips.mp4');
      expect(json['sizeBytes'], 1048576);

      final fromJson = DopamineCustomVideo.fromJson(json);
      expect(fromJson.id, video.id);
      expect(fromJson.name, video.name);
      expect(fromJson.path, video.path);
      expect(fromJson.sizeBytes, video.sizeBytes);
      expect(fromJson, equals(video));
    });

    test('AppSettings defaults dopamineModeEnabled to false and visual to proceduralTunnel', () {
      const settings = AppSettings();
      expect(settings.dopamineModeEnabled, isFalse);
      expect(settings.dopamineVisualType, DopamineVisualType.proceduralTunnel);
      expect(settings.dopamineCustomVideos, isEmpty);
      expect(settings.selectedCustomVideo, isNull);
    });

    test('AppSettings json serialization roundtrip preserves dopamine settings', () {
      final customVideo = DopamineCustomVideo(
        id: 'v1',
        name: 'Satisfying Kinetic Sand',
        path: '/storage/sand.mp4',
        sizeBytes: 204800,
        addedAt: DateTime(2026, 2, 1),
      );

      final settings = AppSettings(
        dopamineModeEnabled: true,
        dopamineVisualType: DopamineVisualType.customVideo,
        dopamineCustomVideos: [customVideo],
        selectedCustomVideoId: 'v1',
      );

      final json = settings.toJson();
      expect(json['dopamineModeEnabled'], isTrue);
      expect(json['dopamineVisualType'], 'customVideo');
      expect((json['dopamineCustomVideos'] as List).length, 1);
      expect(json['selectedCustomVideoId'], 'v1');

      final reconstructed = AppSettings.fromJson(json);
      expect(reconstructed.dopamineModeEnabled, isTrue);
      expect(reconstructed.dopamineVisualType, DopamineVisualType.customVideo);
      expect(reconstructed.dopamineCustomVideos.length, 1);
      expect(reconstructed.selectedCustomVideo?.id, 'v1');
      expect(reconstructed.selectedCustomVideo?.name, 'Satisfying Kinetic Sand');
    });

    test('AppSettings.fromJson handles legacy dopamineVideoSource gracefully', () {
      final reconstructed = AppSettings.fromJson({
        'dopamineModeEnabled': true,
        'dopamineVideoSource': 'minecraftParkour',
      });
      // Legacy video source maps safely to procedural tunnel (built-in default)
      expect(reconstructed.dopamineModeEnabled, isTrue);
      expect(reconstructed.dopamineVisualType, DopamineVisualType.proceduralTunnel);
    });

    test('AppSettings.fromJson falls back to defaults on invalid dopamine values', () {
      final reconstructed = AppSettings.fromJson({
        'dopamineModeEnabled': 'invalid_boolean',
        'dopamineVisualType': 'non_existent_type',
      });
      expect(reconstructed.dopamineModeEnabled, isFalse);
      expect(reconstructed.dopamineVisualType, DopamineVisualType.proceduralTunnel);
      expect(reconstructed.dopamineCustomVideos, isEmpty);
    });
  });

  group('AppSettingsNotifier Dopamine Operations', () {
    test('Notifier mutates visual type and adds/removes custom videos', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(appSettingsProvider.notifier);
      expect(container.read(appSettingsProvider).dopamineModeEnabled, isFalse);

      // 1. Enable dopamine mode
      notifier.setDopamineModeEnabled(true);
      expect(container.read(appSettingsProvider).dopamineModeEnabled, isTrue);

      // 2. Add custom video
      final video1 = DopamineCustomVideo(
        id: 'vid_1',
        name: 'Video 1',
        path: '/storage/1.mp4',
        sizeBytes: 1000,
        addedAt: DateTime.now(),
      );
      notifier.addCustomVideo(video1);

      var state = container.read(appSettingsProvider);
      expect(state.dopamineCustomVideos.length, 1);
      expect(state.selectedCustomVideoId, 'vid_1');
      expect(state.dopamineVisualType, DopamineVisualType.customVideo);
      expect(state.selectedCustomVideo?.name, 'Video 1');

      // 3. Add second video and switch
      final video2 = DopamineCustomVideo(
        id: 'vid_2',
        name: 'Video 2',
        path: '/storage/2.mp4',
        sizeBytes: 2000,
        addedAt: DateTime.now(),
      );
      notifier.addCustomVideo(video2);
      expect(container.read(appSettingsProvider).dopamineCustomVideos.length, 2);
      expect(container.read(appSettingsProvider).selectedCustomVideoId, 'vid_2');

      notifier.selectCustomVideo('vid_1');
      expect(container.read(appSettingsProvider).selectedCustomVideoId, 'vid_1');

      // 4. Remove selected video -> should fallback to remaining video
      notifier.removeCustomVideo('vid_1');
      state = container.read(appSettingsProvider);
      expect(state.dopamineCustomVideos.length, 1);
      expect(state.selectedCustomVideoId, 'vid_2');

      // 5. Remove last remaining video -> should fallback to proceduralTunnel
      notifier.removeCustomVideo('vid_2');
      state = container.read(appSettingsProvider);
      expect(state.dopamineCustomVideos, isEmpty);
      expect(state.selectedCustomVideoId, isNull);
      expect(state.dopamineVisualType, DopamineVisualType.proceduralTunnel);
    });
  });

  group('DopamineTunnelCanvas Widget', () {
    testWidgets('renders infinite procedural neon tunnel and DOPAMINE badge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DopamineTunnelCanvas(
              isAudioPlaying: true,
              width: 300,
              height: 300,
            ),
          ),
        ),
      );

      // Fast forward animation tick
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('DOPAMINE'), findsOneWidget);
      expect(find.byIcon(Icons.bolt), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('synchronizes initial controller offset and handles scrubbing updates', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DopamineTunnelCanvas(
              isAudioPlaying: false,
              playbackPosition: Duration(milliseconds: 1000),
              width: 300,
              height: 300,
            ),
          ),
        ),
      );

      expect(find.byType(DopamineTunnelCanvas), findsOneWidget);

      // Rebuild with scrubbed playbackPosition (> 2 seconds jump)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DopamineTunnelCanvas(
              isAudioPlaying: false,
              playbackPosition: Duration(milliseconds: 5000),
              width: 300,
              height: 300,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(DopamineTunnelCanvas), findsOneWidget);
    });
  });

  group('DopamineVideoCanvas Coordinator Widget', () {
    testWidgets('renders procedural tunnel by default when no custom video is selected and passes playbackPosition', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DopamineVideoCanvas(
              visualType: DopamineVisualType.proceduralTunnel,
              playbackPosition: Duration(seconds: 42),
              isAudioPlaying: true,
              width: 300,
              height: 300,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      final tunnelFinder = find.byType(DopamineTunnelCanvas);
      expect(tunnelFinder, findsOneWidget);
      final DopamineTunnelCanvas tunnelWidget = tester.widget(tunnelFinder);
      expect(tunnelWidget.playbackPosition, const Duration(seconds: 42));
      expect(find.text('DOPAMINE'), findsOneWidget);
    });

    testWidgets('gracefully falls back to procedural tunnel when custom video path is missing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DopamineVideoCanvas(
              visualType: DopamineVisualType.customVideo,
              videoPath: '/non/existent/path/to/video.mp4',
              isAudioPlaying: true,
              width: 300,
              height: 300,
            ),
          ),
        ),
      );

      // Allow async file check to complete
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(DopamineTunnelCanvas), findsOneWidget);
      expect(find.text('Video missing, showing tunnel animation'), findsOneWidget);
    });

    testWidgets('renders badge and responds with custom controller', (tester) async {
      final controller = MockDopamineVideoCanvasController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DopamineVideoCanvas(
              visualType: DopamineVisualType.customVideo,
              videoPath: '/dummy/mock.mp4',
              isAudioPlaying: true,
              width: 300,
              height: 300,
              customController: controller,
            ),
          ),
        ),
      );

      expect(find.text('DOPAMINE'), findsOneWidget);
      expect(find.byIcon(Icons.bolt), findsOneWidget);
    });
  });

  group('DopamineSwitcherSheet Widget', () {
    testWidgets('renders visual options and triggers procedural selection', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: DopamineSwitcherSheet(),
            ),
          ),
        ),
      );

      // Verify header and options
      expect(find.text('Dopamine Mode Visuals'), findsOneWidget);
      expect(find.text('Neon Warp Tunnel'), findsOneWidget);
      expect(find.text('YOUR VIDEOS (0)'), findsOneWidget);
      expect(find.text('Upload Video'), findsOneWidget);

      // Tap Neon Warp Tunnel
      await tester.tap(find.text('Neon Warp Tunnel'));
      await tester.pump();

      expect(container.read(appSettingsProvider).dopamineModeEnabled, isTrue);
      expect(container.read(appSettingsProvider).dopamineVisualType, DopamineVisualType.proceduralTunnel);
    });

    testWidgets('renders custom videos list with selection and delete', (tester) async {
      final customVideo = DopamineCustomVideo(
        id: 'test_vid_1',
        name: 'Cool Gameplay',
        path: '/storage/cool.mp4',
        sizeBytes: 1048576 * 5, // 5MB
        addedAt: DateTime.now(),
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(appSettingsProvider.notifier);
      notifier.addCustomVideo(customVideo);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: DopamineSwitcherSheet(),
            ),
          ),
        ),
      );

      expect(find.text('Cool Gameplay'), findsOneWidget);
      expect(find.text('5.0 MB'), findsOneWidget);

      // Tap on custom video to select it
      await tester.tap(find.text('Cool Gameplay'));
      await tester.pump();

      expect(container.read(appSettingsProvider).dopamineVisualType, DopamineVisualType.customVideo);
      expect(container.read(appSettingsProvider).selectedCustomVideoId, 'test_vid_1');
    });
  });
}
