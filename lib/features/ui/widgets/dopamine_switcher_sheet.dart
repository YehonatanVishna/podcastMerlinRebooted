import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';

/// Modal bottom sheet allowing users to switch between the procedural Neon Warp Tunnel
/// and uploaded custom videos, or upload a new video.
class DopamineSwitcherSheet extends ConsumerWidget {
  const DopamineSwitcherSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DopamineSwitcherSheet(),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<void> _handleUpload(BuildContext context, WidgetRef ref) async {
    final videoService = ref.read(dopamineVideoServiceProvider);
    final messenger = ScaffoldMessenger.of(context);

    final video = await videoService.pickAndImportVideo();
    if (video != null) {
      final notifier = ref.read(appSettingsProvider.notifier);
      notifier.addCustomVideo(video);
      if (!ref.read(appSettingsProvider).dopamineModeEnabled) {
        notifier.setDopamineModeEnabled(true);
      }
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('Added "${video.name}" to Dopamine videos!'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final videoService = ref.read(dopamineVideoServiceProvider);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            children: [
              Icon(Icons.bolt, color: theme.colorScheme.primary, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Dopamine Mode Visuals',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Keep your focus sharp with continuous visuals while listening to podcasts.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // 1. Procedural Option (Default)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: settings.dopamineVisualType == DopamineVisualType.proceduralTunnel
                    ? theme.colorScheme.primary
                    : theme.dividerColor,
                width: settings.dopamineVisualType == DopamineVisualType.proceduralTunnel ? 2 : 1,
              ),
            ),
            child: ListTile(
              leading: Icon(
                Icons.all_inclusive,
                color: theme.colorScheme.primary,
                size: 28,
              ),
              title: const Text('Neon Warp Tunnel'),
              subtitle: const Text('Infinite hypnotic 3D procedural animation'),
              trailing: settings.dopamineVisualType == DopamineVisualType.proceduralTunnel
                  ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                  : null,
              onTap: () {
                notifier.setDopamineVisualType(DopamineVisualType.proceduralTunnel);
                if (!settings.dopamineModeEnabled) {
                  notifier.setDopamineModeEnabled(true);
                }
              },
            ),
          ),

          const SizedBox(height: 12),

          // 2. Custom Videos Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'YOUR VIDEOS (${settings.dopamineCustomVideos.length})',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.8,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Upload Video'),
                onPressed: () => _handleUpload(context, ref),
              ),
            ],
          ),

          if (settings.dopamineCustomVideos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'No custom videos uploaded yet.\nTap "Upload Video" to add your own clips.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: settings.dopamineCustomVideos.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final video = settings.dopamineCustomVideos[index];
                  final isSelected =
                      settings.dopamineVisualType == DopamineVisualType.customVideo &&
                      settings.selectedCustomVideoId == video.id;

                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected ? theme.colorScheme.primary : theme.dividerColor,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: ListTile(
                      leading: Icon(
                        Icons.movie_outlined,
                        color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        video.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_formatBytes(video.sizeBytes)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected)
                            Icon(Icons.check_circle, color: theme.colorScheme.primary),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            tooltip: 'Delete Video',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Video?'),
                                  content: Text('Are you sure you want to remove "${video.name}"?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await videoService.deleteVideo(video);
                                notifier.removeCustomVideo(video.id);
                              }
                            },
                          ),
                        ],
                      ),
                      onTap: () {
                        notifier.selectCustomVideo(video.id);
                        if (!settings.dopamineModeEnabled) {
                          notifier.setDopamineModeEnabled(true);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
