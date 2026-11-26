import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/live_scanner.dart';
import '../vision/camera_frame.dart';
import '../vision/frame_analyzer.dart';
import '../vision/geometry.dart';

/// Full-bleed live camera preview with outlines around detected album
/// covers (FR-01, FR-03).
class LiveCameraView extends StatelessWidget {
  const LiveCameraView({super.key, required this.scanner});

  final LiveScanner scanner;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scanner,
      builder: (context, _) {
        final controller = scanner.controller;
        if (controller == null || !controller.value.isInitialized) {
          return const SizedBox.expand();
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final aspect = scanner.previewAspect;
            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxWidth / aspect,
                      child: CameraPreview(controller),
                    ),
                  ),
                  AnimatedCoverOverlay(
                    key: const Key('scan.coverOverlay'),
                    covers: scanner.covers,
                    sensorDegrees: scanner.sensorDegrees,
                    previewAspect: aspect,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Cover outlines that glide between analysed frames instead of jumping:
/// frames are analysed about five times a second, the screen redraws sixty
/// times. New outlines fade in, lost ones fade out, and an outline kept
/// through a missed frame is drawn fainter.
class AnimatedCoverOverlay extends StatefulWidget {
  const AnimatedCoverOverlay({
    super.key,
    required this.covers,
    required this.sensorDegrees,
    required this.previewAspect,
  });

  final List<CoverSnapshot> covers;
  final int sensorDegrees;
  final double previewAspect;

  @override
  State<AnimatedCoverOverlay> createState() => _AnimatedCoverOverlayState();
}

class _ShownCover {
  _ShownCover(this.target) : quad = target.quad;

  CoverSnapshot target;
  Quad quad;
  double opacity = 0;
  bool present = true;
}

class _AnimatedCoverOverlayState extends State<AnimatedCoverOverlay>
    with SingleTickerProviderStateMixin {
  /// Time constants of the corner and fade animations, in seconds.
  static const _follow = 0.07;
  static const _fade = 0.08;

  late final Ticker _ticker;
  final Map<int, _ShownCover> _shown = {};
  Duration? _last;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _sync();
  }

  @override
  void didUpdateWidget(AnimatedCoverOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.covers != widget.covers) _sync();
  }

  void _sync() {
    final ids = <int>{};
    for (final cover in widget.covers) {
      ids.add(cover.id);
      final shown = _shown.putIfAbsent(cover.id, () => _ShownCover(cover));
      shown
        ..target = cover
        ..present = true;
    }
    for (final entry in _shown.entries) {
      if (!ids.contains(entry.key)) entry.value.present = false;
    }
    if (!_ticker.isActive && _shown.values.any(_moving)) {
      _last = null;
      _ticker.start();
    }
  }

  /// Opacity the outline is heading for.
  static double _goal(_ShownCover s) =>
      !s.present ? 0 : (s.target.detected ? 1 : 0.55);

  /// Whether the outline still has some way to go.
  static bool _moving(_ShownCover s) =>
      (_goal(s) - s.opacity).abs() > 0.01 ||
      s.quad.meanCornerDistance(s.target.quad) > 5e-4;

  void _tick(Duration elapsed) {
    final last = _last;
    _last = elapsed;
    final dt = last == null ? 1 / 60 : (elapsed - last).inMicroseconds / 1e6;
    final move = 1 - math.exp(-dt / _follow);
    final fade = 1 - math.exp(-dt / _fade);
    var busy = false;
    for (final shown in _shown.values) {
      shown
        ..quad = shown.quad.lerp(shown.target.quad, move)
        ..opacity += (_goal(shown) - shown.opacity) * fade;
      if (_moving(shown)) busy = true;
    }
    _shown.removeWhere((_, s) => !s.present && s.opacity < 0.02);
    if (!busy || _shown.isEmpty) _ticker.stop();
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown.values.toList();
    return CustomPaint(
      painter: CoverOverlayPainter(
        covers: [
          for (final s in shown)
            CoverSnapshot(
              id: s.target.id,
              quad: s.quad,
              touchesBorder: s.target.touchesBorder,
              detected: s.target.detected,
              captured: s.target.captured,
              hint: s.target.hint,
            ),
        ],
        opacities: {for (final s in shown) s.target.id: s.opacity},
        sensorDegrees: widget.sensorDegrees,
        previewAspect: widget.previewAspect,
      ),
    );
  }
}

/// Draws each detected cover's outline over a `BoxFit.cover` preview.
class CoverOverlayPainter extends CustomPainter {
  const CoverOverlayPainter({
    required this.covers,
    required this.sensorDegrees,
    required this.previewAspect,
    this.opacities = const {},
  });

  final List<CoverSnapshot> covers;

  /// Opacity of each cover's outline by id (1 when missing).
  final Map<int, double> opacities;
  final int sensorDegrees;
  final double previewAspect;

  /// The outline of [cover] in view coordinates.
  List<Offset> outline(CoverSnapshot cover, Size size) {
    return [
      for (final corner in cover.quad.corners)
        _toOffset(
          previewToView(
            sensorToUpright(corner, sensorDegrees),
            previewAspect: previewAspect,
            viewWidth: size.width,
            viewHeight: size.height,
          ),
        ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final cover in covers) {
      final points = outline(cover, size);
      final path = Path()..addPolygon(points, true);
      final base = cover.touchesBorder
          ? const Color(0xFFFFC107)
          : const Color(0xFF4CAF50);
      final opacity = (opacities[cover.id] ?? 1).clamp(0.0, 1.0);
      final colour = base.withValues(alpha: opacity);
      canvas
        ..drawPath(
          path,
          Paint()
            ..color = base.withValues(alpha: 0.18 * opacity)
            ..style = PaintingStyle.fill,
        )
        ..drawPath(
          path,
          Paint()
            ..color = colour
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.round,
        );
    }
  }

  @override
  bool shouldRepaint(CoverOverlayPainter oldDelegate) =>
      oldDelegate.covers != covers ||
      oldDelegate.opacities != opacities ||
      oldDelegate.sensorDegrees != sensorDegrees ||
      oldDelegate.previewAspect != previewAspect;
}

Offset _toOffset(Point2 p) => Offset(p.x, p.y);
