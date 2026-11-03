import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/vision/cover_detector.dart';
import 'package:jamscan/vision/geometry.dart';
import 'package:jamscan/vision/gray_image.dart';

import 'scene.dart';

const width = 320;
const height = 240;
const detector = CoverDetector();

/// Largest corner error, as a fraction of the frame width.
double cornerError(CoverDetection detection, List<Point2> truth) {
  final found = detection.quad.scale(width.toDouble(), height.toDouble());
  final expected = Quad(truth);
  var worst = 0.0;
  for (var i = 0; i < 4; i++) {
    final d = found.corners[i].distanceTo(expected.corners[i]);
    if (d > worst) worst = d;
  }
  return worst / width;
}

void main() {
  test('finds a frontal cover on a cluttered table', () {
    final truth = square(90, 50, 140);
    final frame = renderScene(
      width: width,
      height: height,
      covers: [PlacedCover(truth, darkArtwork)],
    );

    final found = detector.detect(frame);

    expect(found, hasLength(1));
    expect(cornerError(found.single, truth), lessThan(0.02));
    expect(found.single.touchesBorder, isFalse);
  });

  test('finds a cover photographed at an angle', () {
    // Known limitation: a straight background line (here a plank seam at
    // x = 70) running within about 10 px of a cover side can merge with it
    // and pull that side outwards, so the cover is kept off the seams.
    const truth = [
      Point2(80, 40),
      Point2(250, 62),
      Point2(235, 205),
      Point2(92, 196),
    ];
    final frame = renderScene(
      width: width,
      height: height,
      covers: [PlacedCover(truth, darkArtwork)],
      seed: 3,
    );

    final found = detector.detect(frame);

    expect(found, hasLength(1));
    expect(cornerError(found.single, truth), lessThan(0.025));
  });

  test('returns the outer cover, not the frame printed on it', () {
    final truth = square(80, 40, 160);
    final frame = renderScene(
      width: width,
      height: height,
      covers: [PlacedCover(truth, framedArtwork)],
      clutter: false,
      background: (x, y) => 120,
    );

    final found = detector.detect(frame);

    expect(found, hasLength(1));
    expect(cornerError(found.single, truth), lessThan(0.02));
  });

  test('finds up to three separate covers', () {
    final covers = [
      square(10, 70, 90),
      square(115, 60, 95),
      square(225, 75, 85),
    ];
    final frame = renderScene(
      width: width,
      height: height,
      covers: [for (final c in covers) PlacedCover(c, darkArtwork)],
      seed: 5,
    );

    final found = detector.detect(frame);

    expect(found, hasLength(3));
    for (final truth in covers) {
      final errors = found.map((d) => cornerError(d, truth));
      expect(errors.reduce((a, b) => a < b ? a : b), lessThan(0.02));
    }
  });

  test('ignores scenes without a cover', () {
    final table = renderScene(width: width, height: height, covers: []);
    final flat = renderScene(
      width: width,
      height: height,
      covers: [],
      clutter: false,
    );

    expect(detector.detect(table), isEmpty);
    expect(detector.detect(flat), isEmpty);
  });

  test('rejects long thin rectangles', () {
    const strip = [
      Point2(40, 100),
      Point2(280, 100),
      Point2(280, 160),
      Point2(40, 160),
    ];
    final frame = renderScene(
      width: width,
      height: height,
      covers: [PlacedCover(strip, darkArtwork)],
    );

    expect(detector.detect(frame), isEmpty);
  });

  test('flags covers cut off by the frame edge', () {
    final truth = square(-30, 40, 170);
    final frame = renderScene(
      width: width,
      height: height,
      covers: [PlacedCover(truth, darkArtwork)],
    );

    final found = detector.detect(frame);

    expect(found.every((d) => d.touchesBorder), isTrue);
  });

  test('downscales a padded camera luma plane', () {
    // 8 x 4 image with rows padded to 10 bytes; left half dark.
    final luma = [
      for (var y = 0; y < 4; y++)
        for (var x = 0; x < 10; x++) x < 4 ? 20 : 200,
    ];
    final image = GrayImage.fromLuma(
      Uint8List.fromList(luma),
      width: 8,
      height: 4,
      rowStride: 10,
      maxSide: 4,
    );

    expect(image.width, 4);
    expect(image.height, 2);
    expect(image.pixels, [20, 20, 200, 200, 20, 20, 200, 200]);
  });

  test('analyses a 320 x 240 frame quickly', () {
    final frame = renderScene(
      width: width,
      height: height,
      covers: [PlacedCover(square(90, 50, 140), darkArtwork)],
    );
    detector.detect(frame); // warm up the JIT

    final watch = Stopwatch()..start();
    const runs = 10;
    for (var i = 0; i < runs; i++) {
      detector.detect(frame);
    }
    final perFrame = watch.elapsedMilliseconds / runs;

    // Prints the timing as evidence; the bound is loose for slow CI hosts.
    // ignore: avoid_print
    print('Cover detection: ${perFrame.toStringAsFixed(1)} ms per frame');
    expect(perFrame, lessThan(150));
  });
}
