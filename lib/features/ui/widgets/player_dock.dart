import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/episode.dart';
import '../../../core/providers/app_providers.dart';
import '../../player/audio_player_service.dart';
import 'bidi_text.dart';
import 'cached_image.dart';
import 'now_playing_sheet.dart';
import 'playback_speed_sheet.dart';
import 'queue_bottom_sheet.dart';
import 'sleep_timer_bottom_sheet.dart';

class PlayerDock extends ConsumerStatefulWidget {
  const PlayerDock({super.key});

  @override
  ConsumerState<PlayerDock> createState() => _PlayerDockState();
}

class _PlayerDockState extends ConsumerState<PlayerDock> {
  double? _dragSeconds;

  @override
  Widget build(BuildContext context) {
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
        final podcastTitle = item?.album ?? (episode?.podcastRss.isNotEmpty == true ? 'Podcast' : 'Podcast Merlin');
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
            final currentSeconds = position.inSeconds.clamp(0, maxSeconds).toDouble();
            final progressVal = (currentSeconds / maxSeconds).clamp(0.0, 1.0);
            final displaySec = (_dragSeconds ?? currentSeconds).clamp(0.0, maxSeconds.toDouble());

            return LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 720;

                if (isCompact) {
                  return _buildCompactMiniPlayer(
                    context,
                    audioHandler: audioHandler,
                    title: title,
                    imageUrl: imageUrl,
                    position: position,
                    totalDuration: totalDuration,
                    progress: progressVal,
                    isPlaying: isPlaying,
                    isBuffering: isBuffering,
                  );
                }

                return _buildDesktopPlayerDock(
                  context,
                  constraints: constraints,
                  audioHandler: audioHandler,
                  title: title,
                  podcastTitle: podcastTitle,
                  imageUrl: imageUrl,
                  position: position,
                  totalDuration: totalDuration,
                  maxSeconds: maxSeconds,
                  displaySec: displaySec,
                  isPlaying: isPlaying,
                  isBuffering: isBuffering,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCompactMiniPlayer(
    BuildContext context, {
    required dynamic audioHandler,
    required String title,
    required String imageUrl,
    required Duration position,
    required Duration totalDuration,
    required double progress,
    required bool isPlaying,
    required bool isBuffering,
  }) {
    final theme = Theme.of(context);

    return _MiniPlayerGestureWrapper(
      onSwipeUp: () {
        if (context.mounted) {
          NowPlayingSheet.show(context);
        }
      },
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 4,
        child: InkWell(
          onTap: () => NowPlayingSheet.show(context),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Slim progress bar at the very top of mini player
                LinearProgressIndicator(
                  value: isBuffering ? null : progress,
                  minHeight: 3.0,
                  backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      // Thumbnail Artwork
                      AppCachedImage(
                        imageUrl: imageUrl,
                        width: 44,
                        height: 44,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(width: 12),
                      // Title & Time info with BidiText
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BidiText(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                isBuffering
                                    ? 'Buffering... • ${_formatDuration(position)} / ${_formatDuration(totalDuration)}'
                                    : '${_formatDuration(position)} / ${_formatDuration(totalDuration)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Play / Pause Button
                      IconButton(
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        tooltip: isBuffering ? 'Buffering...' : (isPlaying ? 'Pause' : 'Play'),
                        icon: isBuffering
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: theme.colorScheme.primary,
                                ),
                              )
                            : Icon(
                                isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                size: 36,
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
                      // Fast Forward Button (2-button layout for maximum title width)
                      StreamBuilder<({int rewind, int fastForward})>(
                        stream: audioHandler.seekDurationsStream,
                        initialData: (
                          rewind: audioHandler.rewindDuration,
                          fastForward: audioHandler.fastForwardDuration,
                        ),
                        builder: (context, seekSnapshot) {
                          final forwardSec =
                              seekSnapshot.data?.fastForward ?? audioHandler.fastForwardDuration;
                          return IconButton(
                            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                            icon: _buildForwardIcon(forwardSec),
                            tooltip: 'Forward ${forwardSec}s',
                            onPressed: () => audioHandler.fastForward(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopPlayerDock(
    BuildContext context, {
    required BoxConstraints constraints,
    required MerlinAudioHandler audioHandler,
    required String title,
    required String podcastTitle,
    required String imageUrl,
    required Duration position,
    required Duration totalDuration,
    required int maxSeconds,
    required double displaySec,
    required bool isPlaying,
    required bool isBuffering,
  }) {
    final theme = Theme.of(context);
    final width = constraints.maxWidth;
    final isWide = width >= 1100;
    final zone1Width = isWide ? 260.0 : (width >= 900 ? 210.0 : 170.0);
    final artSize = isWide ? 52.0 : 44.0;

    return Container(
      height: 94,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.2),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.brightness == Brightness.dark ? Colors.black54 : Colors.black12,
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(horizontal: width >= 900 ? 16 : 8, vertical: 8),
      child: Row(
        children: [
          // ==================== ZONE 1: TRACK INFO (Left) ====================
          SizedBox(
            width: zone1Width,
            child: InkWell(
              onTap: () => NowPlayingSheet.show(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                child: Row(
                  children: [
                    AppCachedImage(
                      imageUrl: imageUrl,
                      width: artSize,
                      height: artSize,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    SizedBox(width: isWide ? 12 : 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          BidiText(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: isWide ? 13 : 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isBuffering
                                ? 'Buffering... • ${_formatDuration(position)} / ${_formatDuration(totalDuration)}'
                                : (podcastTitle.isNotEmpty ? podcastTitle : '${_formatDuration(position)} / ${_formatDuration(totalDuration)}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                              fontSize: isWide ? 11 : 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ==================== ZONE 2: TRANSPORT & BOUNDED SCRUBBER (Center) ====================
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Transport Buttons Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Rewind
                        StreamBuilder<({int rewind, int fastForward})>(
                          stream: audioHandler.seekDurationsStream,
                          initialData: (
                            rewind: audioHandler.rewindDuration,
                            fastForward: audioHandler.fastForwardDuration,
                          ),
                          builder: (context, seekSnapshot) {
                            final rewindSec = seekSnapshot.data?.rewind ?? audioHandler.rewindDuration;
                            return IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: _buildRewindIcon(rewindSec),
                              tooltip: 'Rewind ${rewindSec}s',
                              onPressed: () => audioHandler.rewind(),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        // Hero Play/Pause Button
                        IconButton(
                          visualDensity: VisualDensity.standard,
                          tooltip: isBuffering ? 'Buffering...' : (isPlaying ? 'Pause' : 'Play'),
                          icon: isBuffering
                              ? SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: theme.colorScheme.primary,
                                  ),
                                )
                              : Icon(
                                  isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                  size: 40,
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
                        const SizedBox(width: 8),
                        // Fast Forward
                        StreamBuilder<({int rewind, int fastForward})>(
                          stream: audioHandler.seekDurationsStream,
                          initialData: (
                            rewind: audioHandler.rewindDuration,
                            fastForward: audioHandler.fastForwardDuration,
                          ),
                          builder: (context, seekSnapshot) {
                            final forwardSec =
                                seekSnapshot.data?.fastForward ?? audioHandler.fastForwardDuration;
                            return IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: _buildForwardIcon(forwardSec),
                              tooltip: 'Fast forward ${forwardSec}s',
                              onPressed: () => audioHandler.fastForward(),
                            );
                          },
                        ),
                      ],
                    ),
                    // Scrubber with Flanking Timestamps
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        children: [
                          Text(
                            _formatDuration(position),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SizedBox(
                              height: 18,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  trackHeight: 3,
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
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
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDuration(totalDuration),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ==================== ZONE 3: UTILITIES & VOLUME (Right) ====================
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Speed selector
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.speed, size: 20),
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

                  Widget iconWidget = const Icon(Icons.bedtime_outlined, size: 20);
                  if (isActive) {
                    final label = isEnd
                        ? 'End'
                        : (remaining != null ? '${remaining.inMinutes}m' : 'On');
                    iconWidget = Badge(
                      label: Text(label, style: const TextStyle(fontSize: 8)),
                      backgroundColor: theme.colorScheme.primary,
                      child: Icon(Icons.bedtime, size: 20, color: theme.colorScheme.primary),
                    );
                  }

                  return IconButton(
                    visualDensity: VisualDensity.compact,
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
                  Widget iconWidget = const Icon(Icons.queue_music, size: 20);
                  if (queue.isNotEmpty) {
                    iconWidget = Badge(
                      label: Text('${queue.length}', style: const TextStyle(fontSize: 8)),
                      backgroundColor: theme.colorScheme.primary,
                      child: Icon(Icons.queue_music, size: 20, color: theme.colorScheme.primary),
                    );
                  }

                  return IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: iconWidget,
                    tooltip: 'Up Next Queue',
                    onPressed: () => QueueBottomSheet.show(context),
                  );
                },
              ),
              const SizedBox(width: 4),
              // Desktop Volume Slider Control
              _DesktopVolumeControl(audioHandler: audioHandler),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRewindIcon(int seconds) {
    if (seconds == 5) return const Icon(Icons.replay_5);
    if (seconds == 10) return const Icon(Icons.replay_10);
    if (seconds == 30) return const Icon(Icons.replay_30);
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.replay),
        Positioned(
          bottom: 2,
          child: Text(
            '$seconds',
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildForwardIcon(int seconds) {
    if (seconds == 5) return const Icon(Icons.forward_5);
    if (seconds == 10) return const Icon(Icons.forward_10);
    if (seconds == 30) return const Icon(Icons.forward_30);
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.forward),
        Positioned(
          bottom: 2,
          child: Text(
            '$seconds',
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

/// Interactive Volume Control widget with Mute toggle and smooth Slider for Desktop
class _DesktopVolumeControl extends StatefulWidget {
  final MerlinAudioHandler audioHandler;

  const _DesktopVolumeControl({required this.audioHandler});

  @override
  State<_DesktopVolumeControl> createState() => _DesktopVolumeControlState();
}

class _DesktopVolumeControlState extends State<_DesktopVolumeControl> {
  double _lastNonZeroVolume = 1.0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: widget.audioHandler.volumeStream,
      initialData: widget.audioHandler.volume,
      builder: (context, snapshot) {
        final volume = (snapshot.data ?? widget.audioHandler.volume).clamp(0.0, 1.0);

        IconData volumeIcon;
        if (volume <= 0.001) {
          volumeIcon = Icons.volume_off;
        } else if (volume < 0.5) {
          volumeIcon = Icons.volume_down;
        } else {
          volumeIcon = Icons.volume_up;
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(volumeIcon, size: 18),
              tooltip: volume <= 0.001 ? 'Unmute' : 'Mute',
              onPressed: () {
                if (volume <= 0.001) {
                  widget.audioHandler.setVolume(_lastNonZeroVolume > 0.1 ? _lastNonZeroVolume : 1.0);
                } else {
                  _lastNonZeroVolume = volume;
                  widget.audioHandler.setVolume(0.0);
                }
              },
            ),
            SizedBox(
              width: 76,
              height: 20,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  trackHeight: 2.5,
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                ),
                child: Slider(
                  min: 0.0,
                  max: 1.0,
                  value: volume,
                  onChanged: (val) {
                    if (val > 0) _lastNonZeroVolume = val;
                    widget.audioHandler.setVolume(val);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Handles vertical drag gestures (swipe up) on the mobile compact mini-player
/// while ensuring tap events on buttons and the bar continue without interference.
class _MiniPlayerGestureWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onSwipeUp;

  const _MiniPlayerGestureWrapper({
    required this.child,
    required this.onSwipeUp,
  });

  @override
  State<_MiniPlayerGestureWrapper> createState() => _MiniPlayerGestureWrapperState();
}

class _MiniPlayerGestureWrapperState extends State<_MiniPlayerGestureWrapper> {
  double _verticalDelta = 0.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) {
        _verticalDelta = 0.0;
      },
      onVerticalDragUpdate: (details) {
        _verticalDelta += details.delta.dy;
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0.0;
        final isFlingUp = velocity < -150;
        final isDragUp = velocity <= 50 && _verticalDelta < -40;
        if (isFlingUp || isDragUp) {
          widget.onSwipeUp();
        }
        _verticalDelta = 0.0;
      },
      onVerticalDragCancel: () {
        _verticalDelta = 0.0;
      },
      child: widget.child,
    );
  }
}
