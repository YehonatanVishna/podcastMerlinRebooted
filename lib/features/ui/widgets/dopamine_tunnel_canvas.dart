import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Mesmerizing, infinite procedural "Neon Warp Tunnel" canvas for Dopamine Mode.
///
/// Features:
/// - 3D infinite logarithmic tunnel rings with glowing neon edge gradients.
/// - Dynamic starfield warp particles travelling forward through 3D space.
/// - Pulsing focal core synchronized with playback.
/// - Automatically pauses when podcast playback pauses or when app is in the background.
/// - Zero external assets or video codecs required; runs smoothly at native 60/120Hz.
class DopamineTunnelCanvas extends StatefulWidget {
  final bool isAudioPlaying;
  final Duration? playbackPosition;
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const DopamineTunnelCanvas({
    super.key,
    required this.isAudioPlaying,
    this.playbackPosition,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  State<DopamineTunnelCanvas> createState() => _DopamineTunnelCanvasState();
}

class _DopamineTunnelCanvasState extends State<DopamineTunnelCanvas>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    if (widget.playbackPosition != null) {
      const periodMs = 4000;
      final offsetMs = widget.playbackPosition!.inMilliseconds % periodMs;
      _controller.value = offsetMs / periodMs;
    }

    if (widget.isAudioPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant DopamineTunnelCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playbackPosition != null &&
        oldWidget.playbackPosition != null &&
        (widget.playbackPosition! - oldWidget.playbackPosition!).abs() > const Duration(seconds: 2)) {
      const periodMs = 4000;
      final offsetMs = widget.playbackPosition!.inMilliseconds % periodMs;
      _controller.value = offsetMs / periodMs;
    }

    if (oldWidget.isAudioPlaying != widget.isAudioPlaying) {
      if (widget.isAudioPlaying) {
        if (!_controller.isAnimating) {
          _controller.repeat();
        }
      } else {
        if (_controller.isAnimating) {
          _controller.stop(canceled: false);
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (_controller.isAnimating) {
        _controller.stop(canceled: false);
      }
    } else if (state == AppLifecycleState.resumed && widget.isAudioPlaying) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(16);
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final secondaryColor = theme.colorScheme.tertiary.withAlpha(200);

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF070714),
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: theme.brightness == Brightness.dark ? Colors.black87 : Colors.black26,
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
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _TunnelPainter(
                    progress: _controller.value,
                    primaryColor: primaryColor,
                    secondaryColor: secondaryColor,
                  ),
                );
              },
            ),

            // Top badge indicating Dopamine Mode active
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryColor.withValues(alpha: 0.5), width: 1.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt, size: 14, color: primaryColor),
                    const SizedBox(width: 4),
                    Text(
                      'DOPAMINE',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
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

class _TunnelPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color secondaryColor;

  static final List<Point3D> _stars = _generateStars(60);

  _TunnelPainter({
    required this.progress,
    required this.primaryColor,
    required this.secondaryColor,
  });

  static List<Point3D> _generateStars(int count) {
    final rng = math.Random(42);
    final list = <Point3D>[];
    for (int i = 0; i < count; i++) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final dist = 0.1 + rng.nextDouble() * 0.9;
      final speedOffset = rng.nextDouble();
      list.add(Point3D(angle, dist, speedOffset));
    }
    return list;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.sqrt(size.width * size.width + size.height * size.height) / 2;

    // Background gradient with deep cosmic dark center
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          primaryColor.withValues(alpha: 0.15),
          const Color(0xFF03030A),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));
    canvas.drawRect(Offset.zero & size, bgPaint);

    // 1. Draw radial warp perspective guide lines from center
    const rayCount = 12;
    final rayPaint = Paint()
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final rayRot = progress * math.pi * 0.25;
    for (int i = 0; i < rayCount; i++) {
      final angle = (i * 2 * math.pi / rayCount) + rayRot;
      final p2 = Offset(
        center.dx + math.cos(angle) * maxRadius,
        center.dy + math.sin(angle) * maxRadius,
      );

      rayPaint.shader = LinearGradient(
        colors: [
          primaryColor.withValues(alpha: 0.0),
          primaryColor.withValues(alpha: 0.35),
        ],
      ).createShader(Rect.fromPoints(center, p2));

      canvas.drawLine(center, p2, rayPaint);
    }

    // 2. Draw 3D forward-streaming warp particles
    final starPaint = Paint()..style = PaintingStyle.fill;
    for (final star in _stars) {
      final starProgress = (progress + star.speedOffset) % 1.0;
      // Exponential forward acceleration toward the camera
      final depthFactor = math.pow(starProgress, 2.5).toDouble();
      if (depthFactor < 0.02) continue;

      final currentDist = depthFactor * maxRadius * 1.1;
      final starAngle = star.angle + (progress * 0.5);
      final px = center.dx + math.cos(starAngle) * currentDist;
      final py = center.dy + math.sin(starAngle) * currentDist;

      final starAlpha = (depthFactor * 0.9).clamp(0.0, 1.0);
      final starRadius = 0.5 + depthFactor * 2.5;

      starPaint.color = Color.lerp(secondaryColor, Colors.white, depthFactor)!
          .withValues(alpha: starAlpha);
      canvas.drawCircle(Offset(px, py), starRadius, starPaint);
    }

    // 3. Draw logarithmic concentric 3D neon tunnel rings (octagons)
    const ringCount = 14;
    for (int i = 0; i < ringCount; i++) {
      final ringProgress = (progress + (i / ringCount)) % 1.0;
      // Exponential scale expands as ring approaches observer
      final scale = math.pow(ringProgress, 2.8).toDouble();
      if (scale < 0.01) continue;

      final currentRadius = scale * maxRadius * 1.05;
      final ringAlpha = (math.sin(ringProgress * math.pi) * 0.85).clamp(0.0, 1.0);
      final strokeWidth = 1.0 + scale * 3.5;

      // Color shifts from secondary to vibrant primary
      final ringColor = Color.lerp(secondaryColor, primaryColor, ringProgress)!
          .withValues(alpha: ringAlpha);

      final ringPaint = Paint()
        ..color = ringColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke;

      // Slight rotation per ring depth creates a hypnotic vortex twist
      final twistAngle = (1.0 - ringProgress) * 1.5 + (progress * math.pi * 0.5);
      _drawRegularPolygon(canvas, center, currentRadius, 8, twistAngle, ringPaint);
    }

    // 4. Center pulsing glow core
    final corePulse = 0.8 + 0.2 * math.sin(progress * 2 * math.pi * 2);
    final coreRadius = (16.0 * corePulse).clamp(10.0, 28.0);
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.9),
          primaryColor.withValues(alpha: 0.6),
          primaryColor.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius * 2));

    canvas.drawCircle(center, coreRadius * 2, corePaint);
  }

  void _drawRegularPolygon(
    Canvas canvas,
    Offset center,
    double radius,
    int sides,
    double startAngle,
    Paint paint,
  ) {
    final path = Path();
    for (int i = 0; i < sides; i++) {
      final angle = startAngle + (i * 2 * math.pi / sides);
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TunnelPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}

class Point3D {
  final double angle;
  final double dist;
  final double speedOffset;

  Point3D(this.angle, this.dist, this.speedOffset);
}
