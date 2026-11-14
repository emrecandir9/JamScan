import 'dart:math' as math;
import 'dart:typed_data';

import 'package:jamscan/vision/geometry.dart';
import 'package:jamscan/vision/gray_image.dart';
import 'package:jamscan/vision/perspective.dart';

/// Grey level (0-255) of a cover's artwork at `(u, v)` in the unit square.
typedef Artwork = int Function(double u, double v);

/// A cover placed in a synthetic scene, with its true corners in pixels.
class PlacedCover {
  PlacedCover(this.corners, this.artwork);

  /// Clockwise from top-left, in pixels.
  final List<Point2> corners;
  final Artwork artwork;
}

/// Renders [covers] over a textured background into a [width] x [height]
/// greyscale frame, with optional sensor noise.
GrayImage renderScene({
  required int width,
  required int height,
  required List<PlacedCover> covers,
  int seed = 1,
  double noise = 6,
  bool clutter = true,
  int Function(int x, int y)? background,
}) {
  final random = math.Random(seed);
  final pixels = Uint8List(width * height);
  final inverses = [
    for (final cover in covers)
      Homography.fromPoints(cover.corners, const [
        Point2(0, 0),
        Point2(1, 0),
        Point2(1, 1),
        Point2(0, 1),
      ])!,
  ];
  final paint = background ?? (clutter ? _clutteredTable(seed) : _plainWall);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var value = paint(x, y).toDouble();
      for (var i = covers.length - 1; i >= 0; i--) {
        final uv = inverses[i].apply(Point2(x + 0.5, y + 0.5));
        if (uv.x >= 0 && uv.x <= 1 && uv.y >= 0 && uv.y <= 1) {
          value = covers[i].artwork(uv.x, uv.y).toDouble();
          break;
        }
      }
      value += (random.nextDouble() * 2 - 1) * noise;
      pixels[y * width + x] = value.round().clamp(0, 255);
    }
  }
  return GrayImage(width, height, pixels);
}

int _plainWall(int x, int y) => 170;

/// Wood-like stripes plus a few long lines, so the background has edges
/// that must not be mistaken for covers.
int Function(int, int) _clutteredTable(int seed) {
  final random = math.Random(seed * 7919);
  final phase = random.nextDouble() * math.pi;
  return (x, y) {
    final grain = 12 * math.sin(y / 9 + phase + math.sin(x / 40) * 1.5);
    final plank = (x ~/ 70).isEven ? 0 : 14;
    final seam = (x % 70 < 2) ? -45 : 0;
    return (150 + grain + plank + seam).round();
  };
}

/// A dark cover with light shapes, like most record sleeves.
int darkArtwork(double u, double v) {
  final dx = u - 0.5;
  final dy = v - 0.45;
  if (dx * dx + dy * dy < 0.06) return 210;
  if (v > 0.78 && v < 0.86 && u > 0.15 && u < 0.85) return 235;
  return 45;
}

/// A light cover with a dark frame inside it (tests nested outlines).
int framedArtwork(double u, double v) {
  final inFrame = u > 0.2 && u < 0.8 && v > 0.2 && v < 0.8;
  if (!inFrame) return 235;
  return (u * 10).floor().isEven ? 30 : 90;
}

/// Axis-aligned square cover corners.
List<Point2> square(double left, double top, double side) => [
  Point2(left, top),
  Point2(left + side, top),
  Point2(left + side, top + side),
  Point2(left, top + side),
];
