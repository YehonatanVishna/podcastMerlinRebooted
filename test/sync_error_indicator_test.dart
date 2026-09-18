import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/features/ui/widgets/sync_error_banner.dart';

void main() {
  const longErrorMessage =
      'Sync completed, but dead/failing podcast feed(s) were detected:\n'
      'https://deadfeed1.org/rss (HTTP 404)\n'
      'https://deadfeed2.org/rss (SocketException)\n'
      'https://deadfeed3.org/rss (TimeoutException)\n'
      'https://deadfeed4.org/rss (Unknown error)';

  Widget buildTestWidget({
    required String errorMessage,
    String? summary,
    String? title,
    VoidCallback? onDismiss,
    VoidCallback? onRetry,
    bool isWarning = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SyncErrorBanner(
              errorMessage: errorMessage,
              summary: summary,
              title: title,
              onDismiss: onDismiss,
              onRetry: onRetry,
              isWarning: isWarning,
            ),
            const Expanded(
              child: Center(
                child: Text('Main Content Under Banner'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  setUp(() {
    SyncErrorBanner.isModalOpenForTesting = false;
  });

  tearDown(() {
    SyncErrorBanner.isModalOpenForTesting = false;
  });

  group('SyncErrorBanner Compact Indicator Tests', () {
    testWidgets('takes minimal vertical height even with long multiline error message', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          errorMessage: longErrorMessage,
          summary: '4 feeds failed to sync',
        ),
      );
      await tester.pumpAndSettle();

      // Verify compact height: should be around ~42px, well under 56px
      final bannerSize = tester.getSize(find.byType(SyncErrorBanner));
      expect(bannerSize.height, lessThanOrEqualTo(56.0));

      // Verify concise message is displayed
      expect(find.text('4 feeds failed to sync'), findsOneWidget);

      // Verify "Details" action is visible
      expect(find.text('Details'), findsOneWidget);

      // The full multi-line details should NOT be visible on screen yet
      expect(find.text('https://deadfeed1.org/rss (HTTP 404)'), findsNothing);
      expect(find.text('Main Content Under Banner'), findsOneWidget);
    });

    testWidgets('automatically derives concise single-line headline if summary is not provided', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          errorMessage: 'Connection timed out while fetching feed\nDioException: connectTimeout [5000ms]\n#0 ...',
        ),
      );
      await tester.pumpAndSettle();

      final bannerSize = tester.getSize(find.byType(SyncErrorBanner));
      expect(bannerSize.height, lessThanOrEqualTo(56.0));

      // First line extracted as headline
      expect(find.text('Connection timed out while fetching feed'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      // Stack trace lines not visible on the banner
      expect(find.textContaining('DioException'), findsNothing);
    });

    testWidgets('tapping indicator bar opens details modal with full error message', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          errorMessage: longErrorMessage,
          summary: '4 feeds failed to sync',
        ),
      );
      await tester.pumpAndSettle();

      // Tap on the banner (InkWell)
      await tester.tap(find.byType(SyncErrorBanner));
      await tester.pumpAndSettle();

      // Modal bottom sheet should be open
      expect(find.text('Task Failures & Warnings'), findsOneWidget);
      expect(find.text(longErrorMessage), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // Close the modal
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Modal is dismissed
      expect(find.text('Task Failures & Warnings'), findsNothing);
      expect(find.text(longErrorMessage), findsNothing);
    });

    testWidgets('tapping "Details" button opens details modal', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          errorMessage: longErrorMessage,
          summary: 'Some tasks failed',
        ),
      );
      await tester.pumpAndSettle();

      // Tap the "Details" button
      await tester.tap(find.byKey(const Key('sync_error_details_button')));
      await tester.pumpAndSettle();

      // Modal open
      expect(find.text(longErrorMessage), findsOneWidget);

      // Tap close icon in modal header
      await tester.tap(find.byKey(const Key('sync_error_modal_close_icon')));
      await tester.pumpAndSettle();

      // Modal closed
      expect(find.text(longErrorMessage), findsNothing);
    });

    testWidgets('dismiss button on indicator bar triggers onDismiss and does not open modal', (tester) async {
      var dismissed = false;

      await tester.pumpWidget(
        buildTestWidget(
          errorMessage: longErrorMessage,
          summary: '4 feeds failed to sync',
          onDismiss: () => dismissed = true,
        ),
      );
      await tester.pumpAndSettle();

      // Tap dismiss icon on the banner
      await tester.tap(find.byKey(const Key('sync_error_dismiss_button')));
      await tester.pumpAndSettle();

      // onDismiss should have been triggered
      expect(dismissed, isTrue);

      // Details modal should NOT have opened
      expect(find.text('Task Failures & Warnings'), findsNothing);
      expect(find.text(longErrorMessage), findsNothing);
    });

    testWidgets('modal Dismiss button triggers onDismiss and closes modal', (tester) async {
      var dismissed = false;

      await tester.pumpWidget(
        buildTestWidget(
          errorMessage: longErrorMessage,
          onDismiss: () => dismissed = true,
        ),
      );
      await tester.pumpAndSettle();

      // Open details modal
      await tester.tap(find.byKey(const Key('sync_error_details_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sync_error_modal_dismiss_button')), findsOneWidget);

      // Tap dismiss button inside modal
      await tester.tap(find.byKey(const Key('sync_error_modal_dismiss_button')));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
      // Modal should be closed
      expect(find.text('Task Failures & Warnings'), findsNothing);
    });

    testWidgets('modal Retry button triggers onRetry and closes modal', (tester) async {
      var retried = false;

      await tester.pumpWidget(
        buildTestWidget(
          errorMessage: longErrorMessage,
          onRetry: () => retried = true,
        ),
      );
      await tester.pumpAndSettle();

      // Open details modal
      await tester.tap(find.byKey(const Key('sync_error_details_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sync_error_modal_retry_button')), findsOneWidget);

      // Tap retry button inside modal
      await tester.tap(find.byKey(const Key('sync_error_modal_retry_button')));
      await tester.pumpAndSettle();

      expect(retried, isTrue);
      // Modal should be closed
      expect(find.text('Task Failures & Warnings'), findsNothing);
    });

    testWidgets('displays warning styling and custom title when isWarning is true', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          errorMessage: 'Feed timeout',
          summary: '1 feed warning',
          title: 'Feed Sync Warnings',
          isWarning: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 feed warning'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      // Open modal
      await tester.tap(find.byKey(const Key('sync_error_details_button')));
      await tester.pumpAndSettle();

      expect(find.text('Feed Sync Warnings'), findsOneWidget);
    });
  });
}
