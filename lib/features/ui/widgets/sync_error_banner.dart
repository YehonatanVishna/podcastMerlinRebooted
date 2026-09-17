import 'package:flutter/material.dart';

/// A compact, single-line error/warning indicator bar.
///
/// Instead of expanding into a large multiline banner that pushes screen content down,
/// this widget displays a sleek, compact indicator showing a brief summary.
/// Tapping the indicator or its "Details" action opens a modal bottom sheet
/// with the full scrollable, selectable error message and relevant actions.
class SyncErrorBanner extends StatelessWidget {
  final String errorMessage;
  final String? summary;
  final String? title;
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;
  final IconData? icon;
  final bool isWarning;

  const SyncErrorBanner({
    super.key,
    required this.errorMessage,
    this.summary,
    this.title,
    this.onDismiss,
    this.onRetry,
    this.icon,
    this.isWarning = false,
  });

  /// Computes the concise summary displayed on the compact bar.
  String get displaySummary {
    if (summary != null && summary!.trim().isNotEmpty) {
      final firstLine = summary!.trim().split('\n').first.trim();
      return firstLine.isNotEmpty ? firstLine : summary!.trim();
    }
    final trimmed = errorMessage.trim();
    if (trimmed.isEmpty) {
      return isWarning ? 'Task warning' : 'Some tasks failed';
    }
    final firstLine = trimmed.split('\n').firstWhere(
      (line) => line.trim().isNotEmpty,
      orElse: () => trimmed,
    ).trim();

    final cleaned = firstLine.replaceAll(RegExp(r'[:\s]+$'), '').trim();
    return cleaned.isNotEmpty ? cleaned : (isWarning ? 'Task warning' : 'Some tasks failed');
  }

  /// Title shown in the details modal bottom sheet.
  String get displayTitle {
    if (title != null && title!.trim().isNotEmpty) {
      return title!.trim();
    }
    return isWarning ? 'Task Warnings' : 'Task Failures & Warnings';
  }

  static bool _isModalOpen = false;

  @visibleForTesting
  static set isModalOpenForTesting(bool value) => _isModalOpen = value;

  void _showDetails(BuildContext context) async {
    if (_isModalOpen) return;
    _isModalOpen = true;
    try {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: false,
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (modalContext) {
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: 720,
                maxHeight: MediaQuery.of(modalContext).size.height * 0.75,
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        icon ?? (isWarning ? Icons.warning_amber_rounded : Icons.error_outline),
                        color: isWarning
                            ? (isDark ? const Color(0xFFFFD54F) : const Color(0xFFF57F17))
                            : colorScheme.error,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          displayTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('sync_error_modal_close_icon'),
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(modalContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          errorMessage,
                          key: const Key('sync_error_modal_text'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (onRetry != null)
                        FilledButton.tonal(
                          key: const Key('sync_error_modal_retry_button'),
                          onPressed: () {
                            Navigator.of(modalContext).pop();
                            onRetry!();
                          },
                          child: const Text('Retry'),
                        ),
                      if (onDismiss != null)
                        OutlinedButton(
                          key: const Key('sync_error_modal_dismiss_button'),
                          onPressed: () {
                            Navigator.of(modalContext).pop();
                            onDismiss!();
                          },
                          child: const Text('Dismiss'),
                        ),
                      TextButton(
                        key: const Key('sync_error_modal_close_button'),
                        onPressed: () => Navigator.of(modalContext).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    } finally {
      _isModalOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isWarning
        ? (isDark ? const Color(0xFF382A00) : const Color(0xFFFFF3CD))
        : colorScheme.errorContainer;
    final fgColor = isWarning
        ? (isDark ? const Color(0xFFFFD54F) : const Color(0xFF856404))
        : colorScheme.onErrorContainer;

    return Material(
      color: bgColor,
      child: InkWell(
        onTap: () => _showDetails(context),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icon ?? (isWarning ? Icons.warning_amber_rounded : Icons.error_outline),
                  color: fgColor,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    displaySummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: fgColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const Key('sync_error_details_button'),
                  style: TextButton.styleFrom(
                    foregroundColor: fgColor,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _showDetails(context),
                  child: const Text(
                    'Details',
                    style: TextStyle(
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (onDismiss != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    key: const Key('sync_error_dismiss_button'),
                    icon: Icon(Icons.close, color: fgColor, size: 18),
                    tooltip: 'Dismiss error',
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    visualDensity: VisualDensity.compact,
                    onPressed: onDismiss,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
