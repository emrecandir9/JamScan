import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';
import 'gray_image.dart';

/// Sobel gradients of a (blurred) image, kept per axis so edge direction
/// can be checked.
class Gradients {
  Gradients._(this.width, this.height, this.gx, this.gy);

  factory Gradients.of(GrayImage image) {
    final w = image.width;
    final h = image.height;
    final p = image.pixels;
    final gx = Int16List(w * h);
    final gy = Int16List(w * h);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        gx[i] =
            (p[i - w + 1] + 2 * p[i + 1] + p[i + w + 1]) -
            (p[i - w - 1] + 2 * p[i - 1] + p[i + w - 1]);
        gy[i] =
            (p[i + w - 1] + 2 * p[i + w] + p[i + w + 1]) -
            (p[i - w - 1] + 2 * p[i - w] + p[i - w + 1]);
      }
    }
    return Gradients._(w, h, gx, gy);
  }

  final int width;
  final int height;
  final Int16List gx;
  final Int16List gy;

  /// True when the gradient at [index] points along the unit normal
  /// ([nx], [ny]) within about 25 degrees, either way.
  bool alignedWith(int index, double nx, double ny) {
    final x = gx[index].toDouble();
    final y = gy[index].toDouble();
    final dot = x * nx + y * ny;
    return dot * dot >= 0.82 * (x * x + y * y);
  }
}

/// A straight line `x cos(theta) + y sin(theta) = rho`, with theta in
/// [0, pi).
class HoughLine {
  const HoughLine(this.theta, this.rho, this.votes);

  final double theta;
  final double rho;
  final int votes;

  /// Signed distance of a point from the line.
  double distance(double x, double y) =>
      x * math.cos(theta) + y * math.sin(theta) - rho;
}

/// Finds the strongest straight lines among [edges] with a Hough transform.
/// Each edge pixel only votes for directions close to its own gradient,
/// which keeps texture and text from forming lines.
List<HoughLine> houghLines(
  Uint8List edges,
  Gradients gradients, {
  int thetaBins = 90,
  int spread = 3,
  int maxLines = 32,
  int maxPerBand = 6,
  required int minVotes,
}) {
  final w = gradients.width;
  final h = gradients.height;
  final diag = math.sqrt(w * w + h * h).ceil();
  final rhoBins = 2 * diag + 1;
  final cosT = Float64List(thetaBins);
  final sinT = Float64List(thetaBins);
  for (var t = 0; t < thetaBins; t++) {
    final theta = t * math.pi / thetaBins;
    cosT[t] = math.cos(theta);
    sinT[t] = math.sin(theta);
  }
  final acc = Int32List(thetaBins * rhoBins);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      if (edges[i] == 0) continue;
      var phi = math.atan2(gradients.gy[i], gradients.gx[i]);
      if (phi < 0) phi += math.pi;
      final center = (phi / math.pi * thetaBins).round();
      for (var d = -spread; d <= spread; d++) {
        // Bins past either end are the same direction with the normal
        // flipped; rho is computed with that bin's own angle, so it stays
        // consistent.
        final t = (center + d) % thetaBins;
        final rho = x * cosT[t] + y * sinT[t];
        acc[t * rhoBins + (rho + diag).round()]++;
      }
    }
  }

  // Local maxima over a few degrees and pixels.
  final peaks = <HoughLine>[];
  for (var t = 0; t < thetaBins; t++) {
    for (var r = 0; r < rhoBins; r++) {
      final v = acc[t * rhoBins + r];
      if (v < minVotes) continue;
      var isPeak = true;
      for (var dt = -2; dt <= 2 && isPeak; dt++) {
        // Past either end of the angle range the same line has rho negated.
        var tt = t + dt;
        var centre = r;
        if (tt < 0 || tt >= thetaBins) {
          tt = (tt + thetaBins) % thetaBins;
          centre = rhoBins - 1 - r;
        }
        for (var dr = -3; dr <= 3; dr++) {
          final rr = centre + dr;
          if (rr < 0 || rr >= rhoBins || (dt == 0 && dr == 0)) continue;
          final other = acc[tt * rhoBins + rr];
          if (other > v || (other == v && (dt < 0 || (dt == 0 && dr < 0)))) {
            isPeak = false;
            break;
          }
        }
      }
      if (isPeak) {
        peaks.add(HoughLine(t * math.pi / thetaBins, (r - diag).toDouble(), v));
      }
    }
  }
  peaks.sort((a, b) => b.votes.compareTo(a.votes));
  // Stripes, planks or shelves of spines give many strong lines in one
  // direction; cap each 10-degree band so they cannot crowd out a cover's
  // sides.
  final perBand = <int, int>{};
  final kept = <HoughLine>[];
  for (final line in peaks) {
    final band = (line.theta / math.pi * 18).floor() % 18;
    final count = perBand[band] ?? 0;
    if (count >= maxPerBand) continue;
    perBand[band] = count + 1;
    kept.add(line);
    if (kept.length == maxLines) break;
  }
  return kept;
}

/// Angle between two line directions, 0 to pi/2.
double lineAngle(HoughLine a, HoughLine b) {
  final d = (a.theta - b.theta).abs();
  return d > math.pi / 2 ? math.pi - d : d;
}

/// Builds quadrilaterals from two pairs of roughly parallel lines that cross
/// at roughly right angles. Corners must lie inside the frame (with a
/// two-pixel tolerance); they are clamped to it.
List<Quad> quadsFromLines(
  List<HoughLine> lines,
  int width,
  int height, {
  double maxPairAngle = 20 * math.pi / 180,
  double minCrossAngle = 55 * math.pi / 180,
  required double minSeparation,
  int maxPairs = 60,
}) {
  final cx = width / 2;
  final cy = height / 2;
  final pairs = <(HoughLine, HoughLine, int)>[];
  for (var i = 0; i < lines.length; i++) {
    for (var j = i + 1; j < lines.length; j++) {
      final a = lines[i];
      final b = lines[j];
      if (lineAngle(a, b) > maxPairAngle) continue;
      // Distance between the lines, measured through the frame centre.
      final wrapped = (a.theta - b.theta).abs() > math.pi / 2;
      final da = a.distance(cx, cy);
      final db = b.distance(cx, cy) * (wrapped ? -1 : 1);
      if ((da - db).abs() < minSeparation) continue;
      pairs.add((a, b, a.votes + b.votes));
    }
  }
  pairs.sort((p, q) => q.$3.compareTo(p.$3));
  final kept = pairs.take(maxPairs).toList();

  final quads = <Quad>[];
  for (var i = 0; i < kept.length; i++) {
    for (var j = i + 1; j < kept.length; j++) {
      final (a1, a2, _) = kept[i];
      final (b1, b2, _) = kept[j];
      if (lineAngle(a1, b1) < minCrossAngle ||
          lineAngle(a1, b2) < minCrossAngle ||
          lineAngle(a2, b1) < minCrossAngle ||
          lineAngle(a2, b2) < minCrossAngle) {
        continue;
      }
      final corners = <Point2>[];
      for (final (p, q) in [(a1, b1), (a1, b2), (a2, b2), (a2, b1)]) {
        final c = _intersect(p, q);
        if (c == null ||
            c.x < -2 ||
            c.y < -2 ||
            c.x > width + 1 ||
            c.y > height + 1) {
          break;
        }
        corners.add(c);
      }
      // Lines of a pair that cross inside the frame give a bow-tie, not a
      // quadrilateral.
      if (corners.length < 4 || !_convex(corners)) continue;
      quads.add(
        Quad([
          for (final c in corners)
            Point2(
              c.x.clamp(0, width - 1).toDouble(),
              c.y.clamp(0, height - 1).toDouble(),
            ),
        ]),
      );
    }
  }
  return quads;
}

/// Whether the four points, in this order, form a convex quadrilateral.
bool _convex(List<Point2> p) {
  var sign = 0;
  for (var i = 0; i < 4; i++) {
    final a = p[i];
    final b = p[(i + 1) % 4];
    final c = p[(i + 2) % 4];
    final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
    final s = cross > 0 ? 1 : (cross < 0 ? -1 : 0);
    if (s == 0) return false;
    if (sign == 0) {
      sign = s;
    } else if (s != sign) {
      return false;
    }
  }
  return true;
}

Point2? _intersect(HoughLine a, HoughLine b) {
  final c1 = math.cos(a.theta);
  final s1 = math.sin(a.theta);
  final c2 = math.cos(b.theta);
  final s2 = math.sin(b.theta);
  final det = c1 * s2 - s1 * c2;
  if (det.abs() < 1e-6) return null;
  return Point2(
    (a.rho * s2 - s1 * b.rho) / det,
    (c1 * b.rho - a.rho * c2) / det,
  );
}

/// Fraction of points along the segment [a]-[b] (ignoring the ends) that
/// have an edge pixel within two pixels across the segment whose gradient
/// is perpendicular to it.
double orientedSupport(
  Point2 a,
  Point2 b,
  Uint8List edges,
  Gradients gradients, {
  int samples = 28,
}) {
  final w = gradients.width;
  final h = gradients.height;
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length < 1) return 0;
  final nx = -dy / length;
  final ny = dx / length;
  var hits = 0;
  for (var s = 0; s < samples; s++) {
    final t = 0.06 + 0.88 * s / (samples - 1);
    final px = a.x + dx * t;
    final py = a.y + dy * t;
    for (var o = -2; o <= 2; o++) {
      final x = (px + nx * o).round();
      final y = (py + ny * o).round();
      if (x < 0 || y < 0 || x >= w || y >= h) continue;
      final i = y * w + x;
      if (edges[i] != 0 && gradients.alignedWith(i, nx, ny)) {
        hits++;
        break;
      }
    }
  }
  return hits / samples;
}
