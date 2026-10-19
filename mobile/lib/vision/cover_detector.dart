import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';
import 'gray_image.dart';

/// Tunable limits for [CoverDetector]. Areas are fractions of the frame.
class CoverDetectorConfig {
  const CoverDetectorConfig({
    this.edgePercentiles = const [0.70, 0.85, 0.93],
    this.minEdgeStrength = 40,
    this.minArea = 0.03,
    this.maxArea = 0.97,
    this.minAspect = 0.6,
    this.maxAspect = 1.65,
    this.minAngle = 55,
    this.maxAngle = 125,
    this.minFill = 0.88,
    this.minSideSupport = 0.55,
    this.minMeanSupport = 0.7,
    this.maxCovers = 3,
    this.openingRadius = 5,
  });

  /// Edge thresholds, as percentiles of gradient strength. Each one is tried
  /// in turn: the lower one keeps faint cover borders, the higher one
  /// separates a cover from a busy background.
  final List<double> edgePercentiles;

  /// Gradients weaker than this never count as edges (flat scenes).
  final int minEdgeStrength;
  final double minArea;
  final double maxArea;

  /// Covers are square (vinyl) or nearly square (CD); perspective stretches
  /// them, so the accepted width/height range is wide.
  final double minAspect;
  final double maxAspect;

  /// Interior corner angles, in degrees.
  final double minAngle;
  final double maxAngle;

  /// Quad area over the edge region's hull area: low values mean the region
  /// is not shaped like a quadrilateral.
  final double minFill;

  /// Fraction of points along each side that lie on an edge.
  final double minSideSupport;
  final double minMeanSupport;
  final int maxCovers;

  /// Structures thinner than about twice this many pixels are removed
  /// before filled shapes are traced.
  final int openingRadius;
}

/// One detected cover. Corners are normalised to 0-1 in the analysed frame.
class CoverDetection {
  const CoverDetection(this.quad, this.score, {this.touchesBorder = false});

  final Quad quad;

  /// 0-1: how strongly the outline is supported by edges.
  final double score;

  /// True when a corner is at the frame edge, so part of the cover may be
  /// cut off. Such covers are outlined but not captured.
  final bool touchesBorder;
}

/// Finds roughly square, four-cornered outlines (album covers) in a
/// greyscale frame, using classical image processing:
///
/// 1. blur and Sobel gradient magnitude;
/// 2. threshold at a percentile of gradient strength, then dilate to close
///    small gaps;
/// 3. group edge pixels into 8-connected regions;
/// 4. take each region's convex hull and reduce it to four corners;
/// 5. keep quads with plausible size, shape and angles whose sides lie on
///    edges, and drop quads nested inside a better one.
class CoverDetector {
  const CoverDetector([this.config = const CoverDetectorConfig()]);

  final CoverDetectorConfig config;

  List<CoverDetection> detect(GrayImage image) {
    final magnitude = image.blurred().gradientMagnitude();
    final candidates = <_Candidate>[];
    for (final percentile in config.edgePercentiles) {
      final threshold = math.max(
        config.minEdgeStrength,
        _percentile(magnitude, percentile),
      );
      final edges = _dilate(
        _threshold(magnitude, threshold),
        image.width,
        image.height,
      );
      final w = image.width;
      final h = image.height;
      candidates
        ..addAll(_quadsFromRegions(edges, edges, w, h))
        // Closed outlines filled in, with thin lines (table seams, cables,
        // neighbouring sleeves) that touch the cover removed by an opening.
        ..addAll(
          _quadsFromRegions(
            _open(_filledShapes(edges, w, h), w, h, config.openingRadius),
            edges,
            w,
            h,
          ),
        );
    }
    return _suppress(candidates, image.width, image.height);
  }

  /// Turns each 8-connected region of [mask] into a quad candidate, checked
  /// against the [edges] map.
  List<_Candidate> _quadsFromRegions(
    Uint8List mask,
    Uint8List edges,
    int width,
    int height,
  ) {
    final frameArea = width * height.toDouble();
    final labels = Int32List(width * height);
    final stack = Int32List(width * height);
    final found = <_Candidate>[];
    var label = 0;

    for (var start = 0; start < mask.length; start++) {
      if (mask[start] == 0 || labels[start] != 0) continue;
      label++;
      // Flood fill, recording the leftmost and rightmost pixel per row.
      final rowMin = <int, int>{};
      final rowMax = <int, int>{};
      var top = 0;
      stack[top++] = start;
      labels[start] = label;
      var minX = width, maxX = 0, minY = height, maxY = 0;
      while (top > 0) {
        final index = stack[--top];
        final x = index % width;
        final y = index ~/ width;
        if (x < (rowMin[y] ?? width)) rowMin[y] = x;
        if (x > (rowMax[y] ?? -1)) rowMax[y] = x;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= height) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            if (nx < 0 || nx >= width) continue;
            final next = ny * width + nx;
            if (mask[next] != 0 && labels[next] == 0) {
              labels[next] = label;
              stack[top++] = next;
            }
          }
        }
      }

      final boxArea = (maxX - minX + 1) * (maxY - minY + 1);
      if (boxArea < config.minArea * frameArea) continue;

      final outline = <Point2>[
        for (final entry in rowMin.entries)
          Point2(entry.value.toDouble(), entry.key.toDouble()),
        for (final entry in rowMax.entries)
          Point2(entry.value.toDouble(), entry.key.toDouble()),
      ];
      final hull = convexHull(outline);
      final corners = reduceToQuadrilateral(hull);
      if (corners == null) continue;
      final quad = Quad(corners);
      final candidate = _validate(
        quad,
        polygonArea(hull),
        edges,
        width,
        height,
      );
      if (candidate != null) found.add(candidate);
    }
    return found;
  }

  _Candidate? _validate(
    Quad quad,
    double hullArea,
    Uint8List edges,
    int width,
    int height,
  ) {
    final area = quad.area;
    final frameArea = width * height.toDouble();
    if (area < config.minArea * frameArea ||
        area > config.maxArea * frameArea) {
      return null;
    }
    if (hullArea <= 0 || area / hullArea < config.minFill) return null;
    final aspect = quad.aspectRatio;
    if (aspect < config.minAspect || aspect > config.maxAspect) return null;
    if (quad.angles.any((a) => a < config.minAngle || a > config.maxAngle)) {
      return null;
    }

    final support = [
      for (var i = 0; i < 4; i++)
        _sideSupport(
          quad.corners[i],
          quad.corners[(i + 1) % 4],
          edges,
          width,
          height,
        ),
    ];
    final mean = support.reduce((a, b) => a + b) / 4;
    if (support.any((s) => s < config.minSideSupport) ||
        mean < config.minMeanSupport) {
      return null;
    }
    return _Candidate(quad, mean);
  }

  /// Fraction of sample points between [a] and [b] (ignoring the ends,
  /// where corners are rounded or worn) that have an edge pixel within two
  /// pixels.
  double _sideSupport(
    Point2 a,
    Point2 b,
    Uint8List edges,
    int width,
    int height,
  ) {
    const samples = 24;
    var hits = 0;
    for (var i = 0; i < samples; i++) {
      final t = 0.1 + 0.8 * i / (samples - 1);
      final x = (a.x + (b.x - a.x) * t).round();
      final y = (a.y + (b.y - a.y) * t).round();
      if (_edgeNear(x, y, edges, width, height)) hits++;
    }
    return hits / samples;
  }

  bool _edgeNear(int x, int y, Uint8List edges, int width, int height) {
    for (var dy = -2; dy <= 2; dy++) {
      final ny = y + dy;
      if (ny < 0 || ny >= height) continue;
      for (var dx = -2; dx <= 2; dx++) {
        final nx = x + dx;
        if (nx < 0 || nx >= width) continue;
        if (edges[ny * width + nx] != 0) return true;
      }
    }
    return false;
  }

  /// Keeps the best quads, dropping ones that overlap or sit inside a
  /// better one, and normalises the corners.
  List<CoverDetection> _suppress(
    List<_Candidate> candidates,
    int width,
    int height,
  ) {
    candidates.sort((a, b) {
      // Prefer bigger outlines: inner artwork frames are smaller than the
      // cover around them. Edge support breaks ties.
      final byArea = b.quad.area.compareTo(a.quad.area);
      return byArea != 0 ? byArea : b.support.compareTo(a.support);
    });
    final kept = <_Candidate>[];
    for (final candidate in candidates) {
      final overlaps = kept.any(
        (k) =>
            k.quad.contains(candidate.quad.centroid) ||
            candidate.quad.contains(k.quad.centroid) ||
            k.quad.bounds.iou(candidate.quad.bounds) > 0.3,
      );
      if (!overlaps) kept.add(candidate);
      if (kept.length == config.maxCovers) break;
    }
    final margin = 2.0;
    return [
      for (final k in kept)
        CoverDetection(
          k.quad.scale(1 / width, 1 / height),
          k.support,
          touchesBorder: k.quad.corners.any(
            (c) =>
                c.x <= margin ||
                c.y <= margin ||
                c.x >= width - 1 - margin ||
                c.y >= height - 1 - margin,
          ),
        ),
    ];
  }
}

class _Candidate {
  const _Candidate(this.quad, this.support);

  final Quad quad;
  final double support;
}

int _percentile(Uint16List values, double fraction) {
  final histogram = Int32List(2048);
  var counted = 0;
  for (final v in values) {
    if (v > 0) {
      histogram[v]++;
      counted++;
    }
  }
  if (counted == 0) return 0;
  final target = (counted * fraction).floor();
  var seen = 0;
  for (var v = 0; v < histogram.length; v++) {
    seen += histogram[v];
    if (seen > target) return v;
  }
  return histogram.length - 1;
}

Uint8List _threshold(Uint16List magnitude, int threshold) {
  final out = Uint8List(magnitude.length);
  for (var i = 0; i < magnitude.length; i++) {
    if (magnitude[i] >= threshold) out[i] = 1;
  }
  return out;
}

/// 3 x 3 binary dilation.
Uint8List _dilate(Uint8List edges, int width, int height) {
  final out = Uint8List(edges.length);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (edges[y * width + x] == 0) continue;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= height) continue;
        final row = ny * width;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if (nx >= 0 && nx < width) out[row + nx] = 1;
        }
      }
    }
  }
  return out;
}

/// Marks every pixel that cannot be reached from the frame border without
/// crossing an edge: closed outlines become solid shapes.
Uint8List _filledShapes(Uint8List edges, int width, int height) {
  final outside = Uint8List(edges.length);
  final stack = Int32List(edges.length);
  var top = 0;
  void push(int index) {
    if (edges[index] == 0 && outside[index] == 0) {
      outside[index] = 1;
      stack[top++] = index;
    }
  }

  for (var x = 0; x < width; x++) {
    push(x);
    push((height - 1) * width + x);
  }
  for (var y = 0; y < height; y++) {
    push(y * width);
    push(y * width + width - 1);
  }
  while (top > 0) {
    final index = stack[--top];
    final x = index % width;
    final y = index ~/ width;
    if (x > 0) push(index - 1);
    if (x < width - 1) push(index + 1);
    if (y > 0) push(index - width);
    if (y < height - 1) push(index + width);
  }
  final filled = Uint8List(edges.length);
  for (var i = 0; i < filled.length; i++) {
    filled[i] = 1 - outside[i];
  }
  return filled;
}

/// Morphological opening with a (2r + 1)-pixel square: erosion, then
/// dilation.
Uint8List _open(Uint8List mask, int width, int height, int radius) {
  final eroded = _boxFilter(mask, width, height, radius, keepIfAll: true);
  return _boxFilter(eroded, width, height, radius, keepIfAll: false);
}

/// Separable square min (`keepIfAll`) or max filter on a 0/1 mask.
/// Outside the frame counts as 0.
Uint8List _boxFilter(
  Uint8List mask,
  int width,
  int height,
  int radius, {
  required bool keepIfAll,
}) {
  final window = 2 * radius + 1;
  Uint8List pass(Uint8List input, bool horizontal) {
    final out = Uint8List(input.length);
    final lines = horizontal ? height : width;
    final length = horizontal ? width : height;
    for (var line = 0; line < lines; line++) {
      int at(int i) => horizontal ? line * width + i : i * width + line;
      var count = 0;
      for (var i = -radius; i < length + radius; i++) {
        final entering = i + radius;
        if (entering < length && input[at(entering)] != 0) count++;
        final leaving = i - radius - 1;
        if (leaving >= 0 && input[at(leaving)] != 0) count--;
        if (i < 0 || i >= length) continue;
        final keep = keepIfAll ? count == window : count > 0;
        if (keep) out[at(i)] = 1;
      }
    }
    return out;
  }

  return pass(pass(mask, true), false);
}
