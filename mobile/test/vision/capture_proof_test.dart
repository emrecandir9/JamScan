import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jamscan/vision/camera_frame.dart';
import 'package:jamscan/vision/frame_analyzer.dart';
import 'package:jamscan/vision/geometry.dart';
import 'package:jamscan/vision/perspective.dart';

/// Development covers fetched by the backend's `scripts.fetch_dev_covers`.
/// They are copyrighted and not in Git, so this test only runs locally.
final coversDir = Directory('../backend/data/dev/images');

/// Crops written here can be scored by the backend:
/// `python -m scripts.evaluate_recognition ../mobile/build/capture_proof`.
final outputDir = Directory('build/capture_proof');

void main() {
  test(
    'live pipeline captures upright crops of real covers',
    () {
      final files =
          coversDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.jpg'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      if (outputDir.existsSync()) outputDir.deleteSync(recursive: true);
      outputDir.createSync(recursive: true);
      final random = math.Random(7);

      var captured = 0;
      var inFrame = 0;
      var capturedInFrame = 0;
      final framesNeeded = <int>[];
      for (final file in files) {
        final releaseId = file.uri.pathSegments.last.split('.').first;
        final cover = img.decodeJpg(file.readAsBytesSync())!;
        final (upright, corners) = phonePhoto(cover, random);
        final frame = toSensorFrame(upright);
        // Covers cut off by the frame edge are outlined but must not be
        // captured, so they are counted separately.
        final visible = corners.every(
          (c) => c.x > 12 && c.y > 12 && c.x < 708 && c.y < 1268,
        );
        if (visible) inFrame++;

        final analyzer = FrameAnalyzer();
        for (var i = 1; i <= 12; i++) {
          final result = analyzer.analyze(frame);
          if (result.captures.isNotEmpty) {
            captured++;
            if (visible) capturedInFrame++;
            framesNeeded.add(i);
            File('${outputDir.path}/${releaseId}__live.jpg')
                .writeAsBytesSync(result.captures.first.jpeg);
            break;
          }
        }
      }

      // ignore: avoid_print
      print(
        'Captured $captured/${files.length} covers from simulated camera '
        'frames; $capturedInFrame/$inFrame of those fully in frame '
        '(median ${median(framesNeeded)} analysed frames each). '
        'Crops in ${outputDir.path}/',
      );
      expect(capturedInFrame / inFrame, greaterThan(0.75));
    },
    skip: coversDir.existsSync()
        ? false
        : 'Run backend scripts.fetch_dev_covers to enable this test.',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

int median(List<int> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

/// An upright 720 x 1280 colour "photo": the cover tilted and in
/// perspective on a wooden table, with lighting change, slight blur and
/// sometimes a glare spot. Also returns the cover's corners in pixels.
(img.Image, List<Point2>) phonePhoto(img.Image cover, math.Random random) {
  const width = 720;
  const height = 1280;
  final side = width * (0.45 + random.nextDouble() * 0.3);
  final cx = width * (0.4 + random.nextDouble() * 0.2);
  final cy = height * (0.4 + random.nextDouble() * 0.2);
  final angle = (random.nextDouble() * 2 - 1) * 12 * math.pi / 180;
  final jitter = side * 0.06;
  final corners = [
    for (final (dx, dy) in [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)])
      Point2(
        cx +
            (dx * math.cos(angle) - dy * math.sin(angle)) * side +
            (random.nextDouble() * 2 - 1) * jitter,
        cy +
            (dx * math.sin(angle) + dy * math.cos(angle)) * side +
            (random.nextDouble() * 2 - 1) * jitter,
      ),
  ];
  final toCover = Homography.fromPoints(corners, [
    const Point2(0, 0),
    Point2(cover.width.toDouble(), 0),
    Point2(cover.width.toDouble(), cover.height.toDouble()),
    Point2(0, cover.height.toDouble()),
  ])!;
  final light = 0.75 + random.nextDouble() * 0.4;
  final glare = random.nextBool()
      ? Point2(cx + (random.nextDouble() - 0.5) * side * 0.6, cy)
      : null;

  final photo = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final grain = 12 * math.sin(y / 18 + math.sin(x / 80) * 1.5);
      final plank = (x ~/ 140).isEven ? 0 : 14;
      final seam = x % 140 < 3 ? -45 : 0;
      var r = 150 + grain + plank + seam;
      var g = (150 + grain + plank + seam) * 0.78;
      var b = (150 + grain + plank + seam) * 0.55;
      final p = toCover.apply(Point2(x + 0.5, y + 0.5));
      if (p.x >= 0 && p.y >= 0 && p.x < cover.width && p.y < cover.height) {
        final c = cover.getPixel(p.x.floor(), p.y.floor());
        r = c.r.toDouble();
        g = c.g.toDouble();
        b = c.b.toDouble();
      }
      var shine = 0.0;
      if (glare != null) {
        final d = glare.distanceTo(Point2(x.toDouble(), y.toDouble()));
        shine = 160 * math.exp(-d * d / (2 * 60 * 60));
      }
      photo.setPixelRgb(
        x,
        y,
        (r * light + shine).clamp(0, 255).toInt(),
        (g * light + shine).clamp(0, 255).toInt(),
        (b * light + shine).clamp(0, 255).toInt(),
      );
    }
  }
  return (img.gaussianBlur(photo, radius: 1), corners);
}

/// The YUV frame a 90-degree phone sensor delivers for [upright]: rotated
/// a quarter turn anticlockwise, 1280 x 720, NV21-style interleaved chroma.
CameraFrame toSensorFrame(img.Image upright) {
  final width = upright.height;
  final height = upright.width;
  final y = Uint8List(width * height);
  final uv = Uint8List(width * height ~/ 2);
  for (var sy = 0; sy < height; sy++) {
    for (var sx = 0; sx < width; sx++) {
      // Inverse of sensorToUpright for 90 degrees.
      final p = upright.getPixel(upright.width - 1 - sy, sx);
      final r = p.r.toDouble();
      final g = p.g.toDouble();
      final b = p.b.toDouble();
      y[sy * width + sx] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(
        0,
        255,
      );
      if (sx.isEven && sy.isEven) {
        final i = (sy ~/ 2) * width + sx;
        uv[i] = (128 - 0.168736 * r - 0.331264 * g + 0.5 * b).round().clamp(
          0,
          255,
        );
        uv[i + 1] = (128 + 0.5 * r - 0.418688 * g - 0.081312 * b).round().clamp(
          0,
          255,
        );
      }
    }
  }
  return CameraFrame(
    width: width,
    height: height,
    y: y,
    yRowStride: width,
    // Interleaved chroma: U and V views offset by one byte.
    u: uv,
    v: Uint8List.sublistView(uv, 1),
    uvRowStride: width,
    uvPixelStride: 2,
    rotationDegrees: 90,
  );
}
