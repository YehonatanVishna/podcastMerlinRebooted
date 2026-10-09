import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../core/models/app_settings.dart';
import 'dopamine_tunnel_canvas.dart';

/// Pluggable controller interface for Dopamine video rendering.
abstract class DopamineVideoCanvasController {
  bool get isInitialized;
  bool get isPlaying;
  Future<void> play();
  Future<void> pause();
  void dispose();
}

/// Dopamine Mode Canvas coordinator widget.
///
/// Handles two visual modes:
/// 1. [DopamineVisualType.proceduralTunnel] (Default):
///    Infinite, mesmerising procedural "Neon Warp Tunnel" rendered via CustomPainter.
///    Runs at native 60/120Hz with zero asset dependencies or codec overhead.
///
/// 2. [DopamineVisualType.customVideo]:
///    Muted looping user-selected video backed by MediaKit (libmpv/mediacodec).
///    Automatically falls back to procedural tunnel if the video file cannot be found.
///
/// Both modes automatically synchronize playback state with podcast audio
/// and pause when the app is placed in background.
class DopamineVideoCanvas extends StatefulWidget {
  final DopamineVisualType visualType;
  final String? videoPath;
  @Deprecated('Use videoPath instead')
  final String? assetPath;
  final Duration? playbackPosition;
  final bool isAudioPlaying;
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final DopamineVideoCanvasController? customController;

  const DopamineVideoCanvas({
    super.key,
    this.visualType = DopamineVisualType.proceduralTunnel,
    this.videoPath,
    this.assetPath,
    this.playbackPosition,
    required this.isAudioPlaying,
    required this.width,
    required this.height,
    this.borderRadius,
    this.customController,
  });

  @override
  State<DopamineVideoCanvas> createState() => _DopamineVideoCanvasState();
}

class _DopamineVideoCanvasState extends State<DopamineVideoCanvas> with WidgetsBindingObserver {
  Player? _player;
  VideoController? _videoController;
  bool _isInit = false;
  bool _hasError = false;
  bool _isDisposed = false;

  String? get _effectivePath => widget.videoPath ?? widget.assetPath;

  bool get _shouldUseVideo =>
      (widget.visualType == DopamineVisualType.customVideo || widget.customController != null) &&
      (_effectivePath != null && _effectivePath!.isNotEmpty || widget.customController != null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_shouldUseVideo) {
      _initVideo();
    }
  }

  Future<void> _disposeVideo() async {
    final p = _player;
    _player = null;
    _videoController = null;
    _isInit = false;
    _hasError = false;
    await p?.dispose();
  }

  Future<void> _initVideo() async {
    if (widget.customController != null) {
      if (mounted && !_isDisposed) setState(() => _isInit = true);
      return;
    }

    final path = _effectivePath;
    if (path == null || path.isEmpty) {
      if (mounted && !_isDisposed) setState(() => _hasError = true);
      return;
    }

    try {
      final file = File(path).absolute;
      if (!file.existsSync()) {
        debugPrint('[DopamineVideoCanvas] Custom video not found at ${file.path}');
        if (mounted && !_isDisposed) setState(() => _hasError = true);
        return;
      }

      final player = Player();

      // Platform-specific VideoController configuration:
      // On Android: 'mediacodec_embed' with 'mediacodec' renders directly to native Surface.
      // On Linux/Desktop: 'libmpv' with auto hardware decoding.
      final VideoControllerConfiguration config;
      if (Platform.isAndroid) {
        config = const VideoControllerConfiguration(
          vo: 'mediacodec_embed',
          hwdec: 'mediacodec',
          enableHardwareAcceleration: true,
        );
      } else {
        config = const VideoControllerConfiguration(
          vo: 'libmpv',
          hwdec: 'auto',
          enableHardwareAcceleration: true,
        );
      }

      try {
        await (player.platform as dynamic)?.setProperty('vid', 'auto');
        if (!Platform.isAndroid) {
          await (player.platform as dynamic)?.setProperty('vo', 'libmpv');
        }
        await (player.platform as dynamic)?.setProperty('cache', 'no');
      } catch (_) {}

      final videoController = VideoController(
        player,
        configuration: config,
      );

      _player = player;
      _videoController = videoController;

      // Audio track strictly muted so it never interrupts podcast playback
      await player.setVolume(0.0);
      await player.setPlaylistMode(PlaylistMode.loop);

      try {
        await videoController.platform.future.timeout(
          const Duration(seconds: 4),
          onTimeout: () => videoController.platform.future,
        );
      } catch (e) {
        debugPrint('[DopamineVideoCanvas] VideoController platform initialization warning: $e');
      }

      if (!mounted || _isDisposed) {
        await player.dispose();
        return;
      }

      await player.open(Media(file.path), play: widget.isAudioPlaying);

      // Restore continuous position using modulo of video length
      if (widget.playbackPosition != null && widget.playbackPosition! > Duration.zero) {
        _syncPositionToPlayback(player, widget.playbackPosition!);
      }

      // Wait briefly for first frame
      try {
        await videoController.waitUntilFirstFrameRendered.timeout(
          const Duration(seconds: 2),
          onTimeout: () => debugPrint('[DopamineVideoCanvas] First frame render timeout'),
        );
      } catch (_) {}

      if (!mounted || _isDisposed) {
        await player.dispose();
        return;
      }

      setState(() {
        _isInit = true;
        _hasError = false;
      });
    } catch (e, stack) {
      debugPrint('[DopamineVideoCanvas] media_kit init error: $e\n$stack');
      if (mounted && !_isDisposed) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  Future<void> _syncPositionToPlayback(Player player, Duration playbackPos) async {
    try {
      Duration duration = player.state.duration;
      if (duration == Duration.zero) {
        duration = await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 2), onTimeout: () => Duration.zero);
      }
      if (duration > Duration.zero && !_isDisposed) {
        final targetMs = playbackPos.inMilliseconds % duration.inMilliseconds;
        await player.seek(Duration(milliseconds: targetMs));
      }
    } catch (e) {
      debugPrint('[DopamineVideoCanvas] Could not sync modulo position: $e');
    }
  }

  @override
  void didUpdateWidget(covariant DopamineVideoCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);

    final wasUsingVideo = oldWidget.visualType == DopamineVisualType.customVideo || oldWidget.customController != null;
    final nowUsingVideo = _shouldUseVideo;

    if (!wasUsingVideo && nowUsingVideo) {
      _initVideo();
    } else if (wasUsingVideo && !nowUsingVideo) {
      _disposeVideo().then((_) {
        if (mounted && !_isDisposed) setState(() {});
      });
    } else if (nowUsingVideo && widget.customController == null) {
      if (oldWidget.videoPath != widget.videoPath || oldWidget.assetPath != widget.assetPath) {
        if (_player == null) {
          _initVideo();
        } else {
          final path = _effectivePath;
          if (path != null && path.isNotEmpty) {
            final file = File(path).absolute;
            if (file.existsSync()) {
              if (mounted && !_isDisposed) setState(() => _hasError = false);
              _player?.open(Media(file.path), play: widget.isAudioPlaying).then((_) {
                if (widget.playbackPosition != null && _player != null) {
                  _syncPositionToPlayback(_player!, widget.playbackPosition!);
                }
              });
            } else {
              if (mounted && !_isDisposed) setState(() => _hasError = true);
            }
          }
        }
      } else if (oldWidget.isAudioPlaying != widget.isAudioPlaying) {
        if (widget.isAudioPlaying) {
          _player?.play();
        } else {
          _player?.pause();
        }
      } else if (oldWidget.playbackPosition != widget.playbackPosition &&
          widget.playbackPosition != null &&
          oldWidget.playbackPosition != null &&
          (widget.playbackPosition! - oldWidget.playbackPosition!).abs() > const Duration(seconds: 2)) {
        if (_player != null) {
          _syncPositionToPlayback(_player!, widget.playbackPosition!);
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_player == null || !_isInit) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _player?.pause();
    } else if (state == AppLifecycleState.resumed && widget.isAudioPlaying) {
      _player?.play();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final p = _player;
    _player = null;
    _videoController = null;
    p?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If procedural tunnel is chosen or custom video failed/missing, display tunnel
    if (!_shouldUseVideo) {
      return DopamineTunnelCanvas(
        isAudioPlaying: widget.isAudioPlaying,
        playbackPosition: widget.playbackPosition,
        width: widget.width,
        height: widget.height,
        borderRadius: widget.borderRadius,
      );
    }

    final radius = widget.borderRadius ?? BorderRadius.circular(16);
    final theme = Theme.of(context);

    if (_hasError) {
      // Graceful fallback to procedural animation when custom video is missing/corrupted
      return Stack(
        children: [
          DopamineTunnelCanvas(
            isAudioPlaying: widget.isAudioPlaying,
            playbackPosition: widget.playbackPosition,
            width: widget.width,
            height: widget.height,
            borderRadius: widget.borderRadius,
          ),
          Positioned(
            bottom: 8,
            left: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: theme.colorScheme.error),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Video missing, showing tunnel animation',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: theme.brightness == Brightness.dark ? Colors.black54 : Colors.black26,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!_isInit || (_videoController == null && widget.customController == null))
              const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (_videoController != null)
              Video(
                controller: _videoController!,
                fit: BoxFit.cover,
                controls: NoVideoControls,
              )
            else
              // For customController test mock
              Container(color: Colors.black87),

            // Top badge indicating Dopamine Mode active
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24, width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'DOPAMINE',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
