import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/vision/camera_frame.dart';
import 'package:jamscan/vision/frame_analyzer.dart';
import 'package:jamscan/vision/geometry.dart';
import 'package:jamscan/widgets/live_camera_view.dart';

import 'scene.dart';

void main() {
  test('sensor coordinates rotate into the upright preview', () {
    // On a 90-degree back camera, the sensor's top-left is the preview's
    // top-right.
    expect(sensorToUpright(const Point2(0, 0), 90), const Point2(1, 0));
    expect(sensorToUpright(const Point2(1, 0), 90), const Point2(1, 1));
    expect(
      sensorToUpright(const Point2(0.25, 0.5), 0),
      const Point2(0.25, 0.5),
    );
    expect(sensorToUpright(const Point2(0, 0), 270), const Point2(0, 1));
    expect(sensorToUpright(const Point2(0, 0), 180), const Point2(1, 1));
  });

  test('BoxFit.cover crops the preview evenly', () {
    // A 9:16 preview shown in a square view is cropped top and bottom.
    final centre = previewToView(
      const Point2(0.5, 0.5),
      previewAspect: 9 / 16,
      viewWidth: 900,
      viewHeight: 900,
    );
    final top = previewToView(
      const Point2(0, 0),
      previewAspect: 9 / 16,
      viewWidth: 900,
      viewHeight: 900,
    );

    expect(centre, const Point2(450, 450));
    expect(top.x, 0);
    expect(top.y, closeTo(-350, 1e-9)); // (900 - 1600) / 2
  });

  test('the overlay outlines a cover where it appears on screen', () {
    // A cover in the sensor's centre-left, as a 90-degree camera sees it.
    final cover = CoverSnapshot(
      id: 1,
      quad: Quad(const [
        Point2(0.1, 0.4),
        Point2(0.3, 0.4),
        Point2(0.3, 0.6),
        Point2(0.1, 0.6),
      ]),
      touchesBorder: false,
    );
    const painter = CoverOverlayPainter(
      covers: [],
      sensorDegrees: 90,
      previewAspect: 9 / 16,
    );

    final points = painter.outline(cover, const Size(360, 640));

    // Sensor x 0.1-0.3 becomes screen y 0.1-0.3 of 640 px; sensor y 0.4-0.6
    // becomes screen x 0.4-0.6 of 360 px, mirrored.
    final xs = points.map((p) => p.dx);
    final ys = points.map((p) => p.dy);
    expect(xs.reduce((a, b) => a < b ? a : b), closeTo(144, 1e-6));
    expect(xs.reduce((a, b) => a > b ? a : b), closeTo(216, 1e-6));
    expect(ys.reduce((a, b) => a < b ? a : b), closeTo(64, 1e-6));
    expect(ys.reduce((a, b) => a > b ? a : b), closeTo(192, 1e-6));
  });

  test('analyses a padded YUV camera frame end to end', () {
    // 640 x 480 sensor frame with 16 bytes of row padding, like many phones.
    final scene = renderScene(
      width: 640,
      height: 480,
      covers: [PlacedCover(square(200, 120, 240), darkArtwork)],
    );
    const stride = 656;
    final y = Uint8List(stride * 480);
    for (var row = 0; row < 480; row++) {
      y.setRange(row * stride, row * stride + 640, scene.pixels, row * 640);
    }
    final chroma = Uint8List(stride * 240)..fillRange(0, stride * 240, 128);
    final frame = CameraFrame(
      width: 640,
      height: 480,
      y: y,
      yRowStride: stride,
      u: chroma,
      v: chroma,
      uvRowStride: stride,
      uvPixelStride: 2,
    );
    final analyzer = FrameAnalyzer();

    final first = analyzer.analyze(frame);
    final second = analyzer.analyze(frame);

    expect(first.covers, hasLength(1));
    expect(second.covers.single.id, first.covers.single.id);
    final box = second.covers.single.quad.bounds;
    expect(box.left, closeTo(200 / 640, 0.02));
    expect(box.top, closeTo(120 / 480, 0.02));
    expect(box.right, closeTo(440 / 640, 0.02));
    expect(box.bottom, closeTo(360 / 480, 0.02));
    expect(frame.rgbAt(10, 10), (
      frame.lumaAt(10, 10),
      frame.lumaAt(10, 10),
      frame.lumaAt(10, 10),
    ));
  });
}
