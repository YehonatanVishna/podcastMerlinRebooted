import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/episode.dart';
import '../../../core/providers/app_providers.dart';
import '../../downloads/episode_download_service.dart';
import 'cached_image.dart';
import 'episode_description_sheet.dart';
import 'playback_speed_sheet.dart';
import 'queue_bottom_sheet.dart';
import 'sleep_timer_bottom_sheet.dart';

class NowPlayingSheet extends ConsumerStatefulWidget {
  const NowPlayingSheet({super.key});

  static bool _isShowing = false;

  @visibleForTesting
  static set isShowingForTesting(bool value) => _isShowing = value;

  static Future<void> show(BuildContext context) async {
    if (_isShowing) return;
    _isShowing = true;
    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => const NowPlayingSheet(),
      );
    } finally {
      _isShowing = false;
    }
  }

  @override
  ConsumerState<NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends ConsumerState<NowPlayingSheet> {
  double? _dragSeconds;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  bool _isDismissing = false;

  void _dismissIfEmpty() {
    if (_isDismissing || !mounted) return;
    final audioHandler = ref.read(audioHandlerProvider);
    if (audioHandler.mediaItem.value == null && audioHandler.currentEpisode == null) {
      _isDismissing = true;
      Navigator.of(context).maybePop();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final audioHandler = ref.read(audioHandlerProvider);
      _mediaItemSub = audioHandler.mediaItem.listen((item) {
        if (item == null && audioHandler.currentEpisode == null) {
          _dismissIfEmpty();
        }
      });
    });
  }

  @override
  void dispose() {
    _mediaItemSub?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Widget _buildRewindIcon(int seconds) {
    if (seconds == 5) return const Icon(Icons.replay_5, size: 28);
    if (seconds == 10) return const Icon(Icons.replay_10, size: 28);
    if (seconds == 30) return const Icon(Icons.replay_30, size: 28);
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.replay, size: 28),
        Positioned(
          bottom: 2,
          child: Text(
            '$seconds',
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildForwardIcon(int seconds) {
    if (seconds == 5) return const Icon(Icons.forward_5, size: 28);
    if (seconds == 10) return const Icon(Icons.forward_10, size: 28);
    if (seconds == 30) return const Icon(Icons.forward_30, size: 28);
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.forward, size: 28),
        Positioned(
          bottom: 2,
          child: Text(
            '$seconds',
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audioHandler = ref.watch(audioHandlerProvider);

    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      builder: (context, mediaSnapshot) {
        final item = mediaSnapshot.data;
        final episode = audioHandler.currentEpisode;

        if (item == null && episode == null) {
          return const SizedBox.shrink();
        }

        final title = item?.title ?? episode?.title ?? 'Playing Podcast';
        final podcastTitle = item?.album ?? episode?.podcastRss ?? '';
        final imageUrl = (episode?.imageUrl.isNotEmpty == true)
            ? episode!.imageUrl
            : (item?.artUri?.toString() ?? '');
        final totalDuration = item?.duration ?? Duration(seconds: episode?.duration ?? 0);

        return StreamBuilder<PlaybackState>(
          stream: audioHandler.playbackState,
          builder: (context, playbackSnapshot) {
            final state = playbackSnapshot.data;
            final isPlaying = state?.playing ?? false;
            final isBuffering = isPlaying &&
                (state?.processingState == AudioProcessingState.buffering ||
                    state?.processingState == AudioProcessingState.loading);
            final position = state?.position ?? Duration.zero;

            final maxSeconds = totalDuration.inSeconds > 0 ? totalDuration.inSeconds : 1;
            final clampedSec = position.inSeconds.clamp(0, maxSeconds).toDouble();

            return LayoutBuilder(
              builder: (context, constraints) {
                final maxSheetHeight = constraints.maxHeight;
                final artSize = (maxSheetHeight * 0.35).clamp(160.0, 300.0);

                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Drag Handle
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(top: 4, bottom: 8),
                              decoration: BoxDecoration(
                                color: theme.dividerColor.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          // Top bar with close button & title
                          Row(
                            children: [
                              IconButton(
                                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                icon: const Icon(Icons.keyboard_arrow_down, size: 28),
                                tooltip: 'Close Player',
                                onPressed: () => Navigator.pop(context),
                              ),
                              Expanded(
                                child: Text(
                                  podcastTitle.isNotEmpty ? podcastTitle : 'Now Playing',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 48), // Balancing width of close button
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Big Cover Artwork
                          Center(
                            child: Container(
                              width: artSize,
                              height: artSize,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.brightness == Brightness.dark
                                        ? Colors.black54
                                        : Colors.black26,
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: AppCachedImage(
                                  imageUrl: imageUrl,
                                  width: artSize,
                                  height: artSize,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Title & Show metadata
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          if (episode?.publishedAt != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              DateFormat.yMMMMd().format(episode!.publishedAt!),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          // Scrubber Slider
                          Builder(
                            builder: (context) {
                              final displaySec = (_dragSeconds ?? clampedSec).clamp(0.0, maxSeconds.toDouble());
                              final displayPos = _dragSeconds != null
                                  ? Duration(seconds: _dragSeconds!.round())
                                  : position;
                              return Column(
                                children: [
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 4,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                    ),
                                    child: Slider(
                                      min: 0.0,
                                      max: maxSeconds.toDouble(),
                                      value: displaySec,
                                      onChanged: (val) {
                                        setState(() {
                                          _dragSeconds = val;
                                        });
                                      },
                                      onChangeEnd: (val) {
                                        audioHandler.seek(Duration(seconds: val.toInt()));
                                        setState(() {
                                          _dragSeconds = null;
                                        });
                                      },
                                    ),
                                  ),
                                  // Timestamps Row
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDuration(displayPos),
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        Text(
                                          _formatDuration(totalDuration),
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 20,
                            child: isBuffering
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Buffering audio...',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 8),
                          // Primary Playback Controls
                          StreamBuilder<({int rewind, int fastForward})>(
                            stream: audioHandler.seekDurationsStream,
                            initialData: (
                              rewind: audioHandler.rewindDuration,
                              fastForward: audioHandler.fastForwardDuration,
                            ),
                            builder: (context, seekSnapshot) {
                              final rewindSec = seekSnapshot.data?.rewind ?? audioHandler.rewindDuration;
                              final forwardSec = seekSnapshot.data?.fastForward ?? audioHandler.fastForwardDuration;

                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                    iconSize: 36,
                                    icon: _buildRewindIcon(rewindSec),
                                    tooltip: 'Rewind ${rewindSec}s',
                                    onPressed: () => audioHandler.rewind(),
                                  ),
                                  const SizedBox(width: 24),
                                  IconButton(
                                    constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
                                    iconSize: 64,
                                    tooltip: isBuffering ? 'Buffering...' : (isPlaying ? 'Pause' : 'Play'),
                                    icon: isBuffering
                                        ? SizedBox(
                                            width: 48,
                                            height: 48,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 4,
                                              color: theme.colorScheme.primary,
                                            ),
                                          )
                                        : Icon(
                                            isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                            color: theme.colorScheme.primary,
                                          ),
                                    onPressed: () {
                                      if (isPlaying) {
                                        audioHandler.pause();
                                      } else {
                                        audioHandler.play();
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 24),
                                  IconButton(
                                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                    iconSize: 36,
                                    icon: _buildForwardIcon(forwardSec),
                                    tooltip: 'Fast forward ${forwardSec}s',
                                    onPressed: () => audioHandler.fastForward(),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          // Secondary Utility Row: Episode Description, Speed, Sleep Timer, Queue, Download
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Episode Description button
                              IconButton(
                                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                icon: const Icon(Icons.description_outlined),
                                tooltip: 'Episode Description',
                                onPressed: () {
                                  if (episode != null) {
                                    EpisodeDescriptionSheet.show(context, episode);
                                  }
                                },
                              ),
                              // Speed button
                              IconButton(
                                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                icon: const Icon(Icons.speed),
                                tooltip: 'Playback Speed',
                                onPressed: () => PlaybackSpeedSheet.show(context),
                              ),
                              // Sleep Timer button
                              StreamBuilder<Duration?>(
                                stream: audioHandler.sleepTimerStream,
                                initialData: audioHandler.sleepTimerRemaining,
                                builder: (context, sleepSnapshot) {
                                  final isActive = audioHandler.isSleepTimerActive;
                                  final isEnd = audioHandler.isSleepTimerEndOfEpisode;
                                  final remaining = sleepSnapshot.data ?? audioHandler.sleepTimerRemaining;

                                  Widget iconWidget = const Icon(Icons.bedtime_outlined);
                                  if (isActive) {
                                    final label = isEnd
                                        ? 'End'
                                        : (remaining != null ? '${remaining.inMinutes}m' : 'On');
                                    iconWidget = Badge(
                                      label: Text(label, style: const TextStyle(fontSize: 9)),
                                      backgroundColor: theme.colorScheme.primary,
                                      child: Icon(Icons.bedtime, color: theme.colorScheme.primary),
                                    );
                                  }

                                  return IconButton(
                                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                    icon: iconWidget,
                                    tooltip: 'Sleep Timer',
                                    onPressed: () => SleepTimerBottomSheet.show(context),
                                  );
                                },
                              ),
                              // Queue button
                              StreamBuilder<List<Episode>>(
                                stream: audioHandler.queueStream,
                                initialData: audioHandler.currentQueue,
                                builder: (context, queueSnapshot) {
                                  final queue = queueSnapshot.data ?? audioHandler.currentQueue;
                                  Widget iconWidget = const Icon(Icons.queue_music);
                                  if (queue.isNotEmpty) {
                                    iconWidget = Badge(
                                      label: Text('${queue.length}', style: const TextStyle(fontSize: 9)),
                                      backgroundColor: theme.colorScheme.primary,
                                      child: Icon(Icons.queue_music, color: theme.colorScheme.primary),
                                    );
                                  }

                                  return IconButton(
                                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                    icon: iconWidget,
                                    tooltip: 'Up Next Queue',
                                    onPressed: () => QueueBottomSheet.show(context),
                                  );
                                },
                              ),
                              // Download Action button
                              if (episode != null)
                                _NowPlayingDownloadButton(episode: episode),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _NowPlayingDownloadButton extends ConsumerStatefulWidget {
  final Episode episode;

  const _NowPlayingDownloadButton({required this.episode});

  @override
  ConsumerState<_NowPlayingDownloadButton> createState() => _NowPlayingDownloadButtonState();
}

class _NowPlayingDownloadButtonState extends ConsumerState<_NowPlayingDownloadButton> {
  StreamSubscription<DownloadTaskEvent>? _downloadSub;
  late DownloadStatus _status;
  late double _progress;
  String? _downloadPath;
  String? _error;
  int? _resolvedEpisodeId;

  @override
  void initState() {
    super.initState();
    _initDownloadState();
  }

  @override
  void didUpdateWidget(covariant _NowPlayingDownloadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episode.mediaUrl != widget.episode.mediaUrl ||
        oldWidget.episode.id != widget.episode.id) {
      _initDownloadState();
    }
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    super.dispose();
  }

  void _initDownloadState() {
    _resolvedEpisodeId = widget.episode.id;
    _status = widget.episode.downloadStatus;
    _progress = widget.episode.downloadProgress;
    _downloadPath = widget.episode.downloadPath;
    _error = widget.episode.downloadError;

    final downloadService = ref.read(episodeDownloadServiceProvider);

    if (_resolvedEpisodeId != null) {
      final task = downloadService.currentTasks[_resolvedEpisodeId];
      if (task != null) {
        _status = task.status;
        _progress = task.progress;
        _downloadPath = task.downloadPath ?? _downloadPath;
        _error = task.error;
      } else if (downloadService.isEpisodeActive(_resolvedEpisodeId!)) {
        _status = DownloadStatus.downloading;
      } else if (downloadService.isEpisodeQueued(_resolvedEpisodeId!)) {
        _status = DownloadStatus.queued;
      } else if (downloadService.isEpisodePaused(_resolvedEpisodeId!)) {
        _status = DownloadStatus.paused;
      }
    }

    _subscribeToEvents();
    _queryDatabaseState();
  }

  void _subscribeToEvents() {
    _downloadSub?.cancel();
    final downloadService = ref.read(episodeDownloadServiceProvider);
    _downloadSub = downloadService.onDownloadEvent.listen((event) {
      final matches = (event.episodeId == _resolvedEpisodeId) ||
          (event.mediaUrl.isNotEmpty && event.mediaUrl == widget.episode.mediaUrl);
      if (matches && mounted) {
        setState(() {
          _resolvedEpisodeId ??= event.episodeId;
          _status = event.status;
          _progress = event.progress;
          _downloadPath = event.downloadPath ?? _downloadPath;
          _error = event.error;
        });
      }
    });
  }

  Future<void> _queryDatabaseState() async {
    try {
      final db = ref.read(databaseProvider);
      Episode? dbEp;
      if (widget.episode.id != null) {
        dbEp = await db.getEpisodeById(widget.episode.id!);
      }
      if (dbEp == null && widget.episode.guid.isNotEmpty) {
        dbEp = await db.getEpisodeByGuid(widget.episode.guid);
      }
      if (dbEp == null && widget.episode.mediaUrl.isNotEmpty) {
        dbEp = await db.getEpisodeByMediaUrl(widget.episode.mediaUrl);
      }

      if (dbEp != null && mounted) {
        final downloadService = ref.read(episodeDownloadServiceProvider);
        final task = dbEp.id != null ? downloadService.currentTasks[dbEp.id] : null;
        setState(() {
          _resolvedEpisodeId = dbEp!.id;
          if (task != null) {
            _status = task.status;
            _progress = task.progress;
            _downloadPath = task.downloadPath ?? dbEp.downloadPath;
            _error = task.error;
          } else {
            _status = dbEp.downloadStatus;
            _progress = dbEp.downloadProgress;
            _downloadPath = dbEp.downloadPath;
            _error = dbEp.downloadError;
          }
        });
      }
    } catch (_) {}
  }

  Episode _getEffectiveEpisode() {
    return widget.episode.copyWith(
      id: _resolvedEpisodeId ?? widget.episode.id,
      downloadStatus: _status,
      downloadProgress: _progress,
      downloadPath: _downloadPath,
      downloadError: _error,
    );
  }

  void _showDeleteDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Download'),
        content: Text(
          'Remove downloaded episode for "${widget.episode.title}" from device storage?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final messenger = ScaffoldMessenger.of(context);
              final ep = _getEffectiveEpisode();
              await ref.read(episodeDownloadServiceProvider).deleteDownload(ep);
              if (mounted) {
                setState(() {
                  _status = DownloadStatus.none;
                  _progress = 0.0;
                  _downloadPath = null;
                });
                messenger.showSnackBar(
                  SnackBar(content: Text('Removed download for "${widget.episode.title}"')),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloadService = ref.watch(episodeDownloadServiceProvider);

    final isDownloaded = _status == DownloadStatus.downloaded &&
        _downloadPath != null &&
        _downloadPath!.isNotEmpty;
    final isDownloading = _status == DownloadStatus.downloading || _status == DownloadStatus.queued;
    final isPaused = _status == DownloadStatus.paused;
    final isFailed = _status == DownloadStatus.failed;

    if (isDownloaded) {
      return IconButton(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: Icon(
          Icons.download_done_rounded,
          color: theme.colorScheme.primary,
        ),
        tooltip: 'Downloaded • Tap to manage',
        onPressed: () => _showDeleteDialog(context),
      );
    } else if (isDownloading) {
      final isQueued = _status == DownloadStatus.queued;
      final pct = (_progress * 100).toInt();
      return IconButton(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: SizedBox(
          width: 24,
          height: 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: (_progress > 0 && !isQueued) ? _progress : null,
                strokeWidth: 2.5,
              ),
              Icon(
                isQueued ? Icons.hourglass_top : Icons.close,
                size: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        tooltip: isQueued
            ? 'Queued for download • Tap to cancel'
            : 'Downloading ($pct%) • Tap to cancel',
        onPressed: () {
          final epId = _resolvedEpisodeId ?? widget.episode.id;
          if (epId != null) {
            downloadService.cancelDownload(epId);
          }
          setState(() {
            _status = DownloadStatus.none;
            _progress = 0.0;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Download cancelled')),
          );
        },
      );
    } else if (isPaused) {
      return IconButton(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: const Icon(Icons.play_circle_outline, color: Colors.blue),
        tooltip: 'Download paused • Tap to resume',
        onPressed: () {
          final ep = _getEffectiveEpisode();
          downloadService.resumeDownload(ep);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Resuming download...')),
          );
        },
      );
    } else if (isFailed) {
      return IconButton(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: const Icon(Icons.refresh, color: Colors.orange),
        tooltip: 'Download failed (${_error ?? "Tap to retry"})',
        onPressed: () {
          setState(() {
            _status = DownloadStatus.queued;
          });
          final ep = _getEffectiveEpisode();
          downloadService.startDownload(ep);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Retrying download for "${widget.episode.title}"')),
          );
        },
      );
    } else {
      return IconButton(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: const Icon(Icons.download_outlined),
        tooltip: 'Download Episode',
        onPressed: () {
          setState(() {
            _status = DownloadStatus.queued;
          });
          final ep = _getEffectiveEpisode();
          downloadService.startDownload(ep);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Starting download for "${widget.episode.title}"')),
          );
        },
      );
    }
  }
}
