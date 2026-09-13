import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/providers/app_providers.dart';
import '../widgets/cached_image.dart';

class PlaybackHistoryView extends ConsumerWidget {
  const PlaybackHistoryView({super.key});

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0:00';
    final d = Duration(seconds: seconds);
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$secs';
    }
    return '$minutes:$secs';
  }

  String _formatPlayedDate(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0 && now.day == dt.day) {
      return 'Today at ${DateFormat.jm().format(dt)}';
    } else if (diff.inDays <= 1 && (now.day - dt.day == 1 || diff.inHours < 24)) {
      return 'Yesterday at ${DateFormat.jm().format(dt)}';
    } else if (diff.inDays < 7) {
      return '${DateFormat.E().format(dt)} at ${DateFormat.jm().format(dt)}';
    } else {
      return DateFormat.yMMMd().add_jm().format(dt);
    }
  }

  Future<void> _confirmClearHistory(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Playback History?'),
        content: const Text('This will remove all episodes from your playback history. Your subscriptions and downloaded files will remain intact.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(playbackHistoryProvider.notifier).clearAllHistory();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Playback history cleared')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(playbackHistoryProvider);
    final audioHandler = ref.watch(audioHandlerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playback History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh History',
            onPressed: () => ref.read(playbackHistoryProvider.notifier).loadHistory(),
          ),
          if (historyState.history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear All History',
              onPressed: () => _confirmClearHistory(context, ref),
            ),
        ],
      ),
      body: historyState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : historyState.error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text('Failed to load history: ${historyState.error}'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => ref.read(playbackHistoryProvider.notifier).loadHistory(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : historyState.history.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history,
                              size: 64,
                              color: Theme.of(context).disabledColor,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No Playback History Yet',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Episodes you play or mark as played will appear here.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => ref.read(playbackHistoryProvider.notifier).loadHistory(),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: historyState.history.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                        itemBuilder: (context, index) {
                          final ep = historyState.history[index];
                          final isFinished = ep.isFinished;
                          final showProgress = ep.position > 0 && !isFinished && ep.duration > 0;
                          final progress = ep.duration > 0 ? (ep.position / ep.duration).clamp(0.0, 1.0) : 0.0;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            onTap: () => audioHandler.playEpisode(ep),
                            leading: Stack(
                              children: [
                                AppCachedImage(
                                  imageUrl: ep.imageUrl,
                                  width: 52,
                                  height: 52,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                if (isFinished)
                                  Positioned(
                                    right: 2,
                                    bottom: 2,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.check_circle,
                                        size: 14,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(
                              ep.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: isFinished ? Theme.of(context).disabledColor : null,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                if (ep.historyPlayedAt != null)
                                  Text(
                                    _formatPlayedDate(ep.historyPlayedAt),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.primary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    if (isFinished)
                                      Text(
                                        'Completed • ${_formatDuration(ep.duration)}',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: Colors.grey,
                                            ),
                                      )
                                    else if (ep.position > 0 && ep.duration > 0)
                                      Text(
                                        '${_formatDuration(ep.position)} / ${_formatDuration(ep.duration)}',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      )
                                    else if (ep.duration > 0)
                                      Text(
                                        _formatDuration(ep.duration),
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                                if (showProgress) ...[
                                  const SizedBox(height: 4),
                                  LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 3,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ],
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(isFinished ? Icons.replay : Icons.play_arrow),
                                  tooltip: isFinished ? 'Replay' : 'Play',
                                  onPressed: () => audioHandler.playEpisode(ep),
                                ),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 20),
                                  tooltip: 'Options',
                                  onSelected: (val) async {
                                    if (val == 'remove_history') {
                                      if (ep.id != null) {
                                        await ref.read(playbackHistoryProvider.notifier).removeFromHistory(ep.id!);
                                      }
                                    } else if (val == 'toggle_played') {
                                      final newPlayed = !ep.isFinished;
                                      if (ep.id != null) {
                                        await ref.read(databaseProvider).setEpisodePlayed(ep.id!, newPlayed);
                                        await ref.read(playbackHistoryProvider.notifier).loadHistory();
                                      }
                                    } else if (val == 'play_next') {
                                      audioHandler.addToQueue(ep, playNext: true);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Playing next: ${ep.title}')),
                                      );
                                    } else if (val == 'add_queue') {
                                      audioHandler.addToQueue(ep, playNext: false);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Added to queue: ${ep.title}')),
                                      );
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    PopupMenuItem(
                                      value: 'toggle_played',
                                      child: Row(
                                        children: [
                                          Icon(
                                            ep.isFinished ? Icons.check_circle_outline : Icons.check_circle,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Text(ep.isFinished ? 'Mark as Unplayed' : 'Mark as Played'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'play_next',
                                      child: Row(
                                        children: [
                                          Icon(Icons.playlist_play, size: 20),
                                          SizedBox(width: 12),
                                          Text('Play Next'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'add_queue',
                                      child: Row(
                                        children: [
                                          Icon(Icons.queue_music, size: 20),
                                          SizedBox(width: 12),
                                          Text('Add to Queue'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuDivider(),
                                    const PopupMenuItem(
                                      value: 'remove_history',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                          SizedBox(width: 12),
                                          Text('Remove from History', style: TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
