import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/vision/cover_detector.dart';
import 'package:jamscan/vision/geometry.dart';
import 'package:jamscan/vision/gray_image.dart';
import 'package:jamscan/vision/line_quads.dart';

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

  test('finds a sleeve held by hands', () {
    final truth = square(95, 45, 130);
    final frame = renderScene(
      width: width,
      height: height,
      covers: [PlacedCover(truth, darkArtwork)],
    );
    // Hands reach in from both sides and cover part of the left and right
    // edges, joining the sleeve's outline to the background's.
    void hand(int left, int top, int w, int h) {
      for (var y = top; y < top + h; y++) {
        for (var x = left; x < left + w; x++) {
          frame.pixels[y * width + x] = 150;
        }
      }
    }

    hand(55, 90, 55, 40);
    hand(210, 100, 70, 45);

    final found = detector.detect(frame);

    expect(found, hasLength(1));
    expect(cornerError(found.single, truth), lessThan(0.025));
  });

  test('ignores shelves full of record spines', () {
    final shelves = renderScene(
      width: width,
      height: height,
      covers: [],
      background: (x, y) {
        if (y % 80 < 3) return 40; // shelf edges
        return (x % 9 < 2) ? 60 : 120 + (x * 37 % 50); // spines
      },
    );

    expect(detector.detect(shelves), isEmpty);
  });

  group('a shape closed off by a sleeve\'s edge', () {
    // A sleeve held up in front of a door: the door's sides, cut off by the
    // top of the frame, and the sleeve's top edge close a second square.
    final sleeve = square(105, 110, 110);
    int door(int x, int y) {
      if (x < 90 || x >= 230 || y >= 110) return 170;
      return y < 3 ? 60 : 110; // the lintel, at the top of the frame
    }

    test('is not reported when the sleeve is seen', () {
      final frame = renderScene(
        width: width,
        height: height,
        covers: [PlacedCover(sleeve, darkArtwork)],
        background: door,
      );

      final found = detector.detect(frame);

      expect(found, hasLength(1));
      expect(cornerError(found.single, sleeve), lessThan(0.02));
    });

    test('is not reported while the sleeve is only tracked', () {
      // The sleeve is missed in this frame (it matches the wall), but the
      // tracker still has it.
      final frame = renderScene(
        width: width,
        height: height,
        covers: [PlacedCover(sleeve, (u, v) => 170)],
        background: door,
      );
      final tracked = Quad(sleeve).scale(1 / width, 1 / height);

      expect(detector.detect(frame), hasLength(1));
      expect(detector.detect(frame, priors: [tracked]), isEmpty);
    });

    test('gives way to a sleeve found after it', () {
      // A hand hides half of the sleeve's left side, so the door's square
      // ranks above the sleeve. It is kept first and must then make way.
      int handOnSide(double u, double v) =>
          u < 0.1 && (v - 0.5).abs() < 0.25 ? 170 : 30;
      final frame = renderScene(
        width: width,
        height: height,
        covers: [PlacedCover(sleeve, handOnSide)],
        background: door,
      );

      final found = detector.detect(frame);

      expect(found, hasLength(1));
      expect(cornerError(found.single, sleeve), lessThan(0.04));
    });
  });

  test('ignores a shelf compartment full of record spines', () {
    final frame = renderScene(
      width: width,
      height: height,
      covers: [],
      clutter: false,
      background: (x, y) {
        final inside = x >= 100 && x < 220 && y >= 60 && y < 180;
        final board = x >= 92 && x < 228 && y >= 52 && y < 188;
        if (inside) return x % 8 < 2 ? 50 : 110 + (x * 37 % 40);
        return board ? 60 : 170;
      },
    );

    expect(detector.detect(frame), isEmpty);
  });

  test('still finds a cover with rows of lettering', () {
    final truth = square(95, 45, 140);
    // Eight lines of capitals: letters with gaps between them. Solid bars
    // this close together would read as shelves.
    int lettering(double u, double v) {
      final line = (v * 16).floor().isOdd && u > 0.12 && u < 0.88;
      final letter = (u * 30).floor() % 3 != 2;
      return line && letter ? 230 : 40;
    }

    final frame = renderScene(
      width: width,
      height: height,
      covers: [PlacedCover(truth, lettering)],
    );

    final found = detector.detect(frame);

    expect(found, hasLength(1));
    expect(cornerError(found.single, truth), lessThan(0.02));
  });

  test('a near-vertical edge gives one line, not one at each end of the '
      'angle range', () {
    // Tilted by one degree: its direction lies between the bins at 0 and
    // 178 degrees, where the angle range wraps round.
    final image = GrayImage(width, height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.pixels[y * width + x] = x < 150 + y * 0.0175 ? 60 : 200;
      }
    }
    final gradients = Gradients.of(image);
    final edges = Uint8List(width * height);
    for (var i = 0; i < edges.length; i++) {
      if (gradients.gx[i].abs() > 100) edges[i] = 1;
    }

    final lines = houghLines(edges, gradients, minVotes: 100);

    expect(lines, hasLength(1));
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
