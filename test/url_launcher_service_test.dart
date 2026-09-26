// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:podcast_merlin_flutter/core/services/url_launcher_service.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class MockUrlLauncherPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  String? launchedUrl;
  bool shouldSucceed = true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrl = url;
    if (!shouldSucceed) {
      return false;
    }
    return true;
  }
}

void main() {
  late MockUrlLauncherPlatform mockPlatform;

  setUp(() {
    mockPlatform = MockUrlLauncherPlatform();
    UrlLauncherPlatform.instance = mockPlatform;
  });

  group('UrlLauncherService', () {
    testWidgets('prepends https:// when missing scheme', (tester) async {
      final success = await UrlLauncherService.launchWebUrl('example.com/podcast');
      expect(success, isTrue);
      expect(mockPlatform.launchedUrl, 'https://example.com/podcast');
    });

    testWidgets('preserves http:// and https:// schemes and trims whitespace', (tester) async {
      final successHttp = await UrlLauncherService.launchWebUrl('   http://myfeed.com/rss   ');
      expect(successHttp, isTrue);
      expect(mockPlatform.launchedUrl, 'http://myfeed.com/rss');

      final successHttps = await UrlLauncherService.launchWebUrl('   https://secure.com   ');
      expect(successHttps, isTrue);
      expect(mockPlatform.launchedUrl, 'https://secure.com');
    });

    testWidgets('shows snackbar and returns false when url is empty or whitespace', (tester) async {
      late BuildContext buildCtx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                buildCtx = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final success = await UrlLauncherService.launchWebUrl('   ', context: buildCtx);
      expect(success, isFalse);
      await tester.pumpAndSettle();

      expect(find.text('Could not open website'), findsOneWidget);
    });

    testWidgets('shows snackbar when launchUrl returns false', (tester) async {
      mockPlatform.shouldSucceed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => UrlLauncherService.launchWebUrl('https://fail.com', context: context),
                child: const Text('Launch'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();

      expect(find.text('Could not open website'), findsOneWidget);
    });
  });
}
