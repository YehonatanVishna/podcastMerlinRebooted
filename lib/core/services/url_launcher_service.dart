import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Centralized service for launching external URLs safely across platforms.
class UrlLauncherService {
  UrlLauncherService._();

  /// Launches a web URL in an external browser application.
  ///
  /// Automatically normalizes URLs lacking an `http://` or `https://` prefix to `https://`.
  /// If launching fails and [context] is provided and mounted, a user-facing [SnackBar] with
  /// 'Could not open website' is shown.
  /// Returns `true` if launched successfully, `false` otherwise.
  static Future<bool> launchWebUrl(
    String rawUrl, {
    BuildContext? context,
  }) async {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return _fail(context);
    }

    final lower = trimmed.toLowerCase();
    final sanitizedUrl = (lower.startsWith('http://') || lower.startsWith('https://'))
        ? trimmed
        : 'https://$trimmed';

    final uri = Uri.tryParse(sanitizedUrl);
    if (uri == null) {
      return _fail(context);
    }

    try {
      final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!success) {
        if (context != null && context.mounted) {
          _fail(context);
        }
        return false;
      }
      return true;
    } catch (_) {
      if (context != null && context.mounted) {
        _fail(context);
      }
      return false;
    }
  }

  static bool _fail(BuildContext? context) {
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open website')),
      );
    }
    return false;
  }
}
