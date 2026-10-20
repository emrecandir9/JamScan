import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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
                  CustomPaint(
                    key: const Key('scan.coverOverlay'),
                    painter: CoverOverlayPainter(
                      covers: scanner.covers,
                      sensorDegrees: scanner.sensorDegrees,
                      previewAspect: aspect,
                    ),
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

/// Draws each detected cover's outline over a `BoxFit.cover` preview.
class CoverOverlayPainter extends CustomPainter {
  const CoverOverlayPainter({
    required this.covers,
    required this.sensorDegrees,
    required this.previewAspect,
  });

  final List<CoverSnapshot> covers;
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
      final colour = cover.touchesBorder
          ? const Color(0xFFFFC107)
          : const Color(0xFF4CAF50);
      canvas
        ..drawPath(
          path,
          Paint()
            ..color = colour.withValues(alpha: 0.18)
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
      oldDelegate.sensorDegrees != sensorDegrees ||
      oldDelegate.previewAspect != previewAspect;
}

Offset _toOffset(Point2 p) => Offset(p.x, p.y);
