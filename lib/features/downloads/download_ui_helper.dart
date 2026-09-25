import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/episode.dart';
import '../../core/providers/app_providers.dart';

Future<void> triggerDownloadWithFeedback({
  required BuildContext context,
  required WidgetRef ref,
  required Episode episode,
  bool isResume = false,
  bool isRetry = false,
}) async {
  final unmeteredOnly = ref.read(downloadOnlyOnUnmeteredProvider);
  bool isMetered = false;
  if (unmeteredOnly) {
    try {
      final isUnmetered = await ref.read(connectivityServiceProvider).isUnmetered();
      isMetered = !isUnmetered;
    } catch (_) {}
  }

  final service = ref.read(episodeDownloadServiceProvider);
  if (isResume) {
    service.resumeDownload(episode);
  } else {
    service.startDownload(episode);
  }

  if (context.mounted) {
    if (isMetered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download queued: Waiting for unmetered Wi-Fi connection'),
        ),
      );
    } else {
      final prefix = isRetry
          ? 'Retrying download for'
          : (isResume ? 'Resuming download for' : 'Starting download for');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$prefix "${episode.title}"'),
        ),
      );
    }
  }
}
