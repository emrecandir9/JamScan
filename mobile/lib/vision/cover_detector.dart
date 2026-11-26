import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';
import 'gray_image.dart';
import 'line_quads.dart';
import 'perspective.dart';

/// Tunable limits for [CoverDetector]. Areas are fractions of the frame.
class CoverDetectorConfig {
  const CoverDetectorConfig({
    this.edgePercentiles = const [0.70, 0.85, 0.93],
    this.minEdgeStrength = 40,
    this.minArea = 0.06,
    this.maxArea = 0.97,
    this.minAspect = 0.69,
    this.maxAspect = 1.45,
    this.minAngle = 60,
    this.maxAngle = 120,
    this.minFill = 0.88,
    this.minSideSupport = 0.45,
    this.minMeanSupport = 0.7,
    this.maxCovers = 3,
    this.openingRadius = 5,
    this.cannyHighPercentile = 0.8,
    this.cannyLowRatio = 0.35,
    this.minOrientedSide = 0.3,
    this.minOrientedMean = 0.55,
    this.priorBonus = 0.3,
    this.minBorderCutSide = 0.5,
    this.extensionLength = 0.25,
    this.maxExtension = 0.5,
    this.strongExtension = 0.7,
    this.maxSpines = 0.8,
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

  /// The smaller of quad and hull area over the larger one: low values mean
  /// the region is not shaped like a quadrilateral.
  final double minFill;

  /// Fraction of points along each side that lie on an edge.
  final double minSideSupport;
  final double minMeanSupport;
  final int maxCovers;

  /// Structures thinner than about twice this many pixels are removed
  /// before filled shapes are traced.
  final int openingRadius;

  /// Canny hysteresis: strong edges are above this percentile of thinned
  /// gradient strength; weak ones above [cannyLowRatio] of that are kept
  /// when connected to a strong one.
  final double cannyHighPercentile;
  final double cannyLowRatio;

  /// Final check of every candidate: the fraction of each side (and of all
  /// four on average) that lies on an edge running along that side. Hands
  /// holding a sleeve hide part of a side, so a single side may be weak.
  final double minOrientedSide;
  final double minOrientedMean;

  /// Extra weight, up to this fraction, for an outline close to a cover
  /// tracked in earlier frames, so the outline does not jump to a
  /// competing shape.
  final double priorBonus;

  /// For a cover cut off by the frame edge: the support each of its three
  /// visible sides needs.
  final double minBorderCutSide;

  /// How far past each corner, as a fraction of the side, edges are looked
  /// for, and the largest average support allowed there. Outlines whose
  /// sides carry on past the corners are built from longer lines (shelves,
  /// spines, seams) rather than a sleeve.
  final double extensionLength;
  final double maxExtension;

  /// Support past a single corner end above which the line clearly runs on.
  final double strongExtension;

  /// Shelves and crates of records: an outline is rejected when this
  /// share of its inside, or more, is crossed from side to side by straight
  /// lines parallel to its sides (record spines).
  final double maxSpines;
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

  /// Finds covers in [image]. [priors] are outlines (normalised to 0-1)
  /// of covers tracked in earlier frames; candidates close to one are
  /// preferred.
  List<CoverDetection> detect(GrayImage image, {List<Quad> priors = const []}) {
    final w = image.width;
    final h = image.height;
    final blurred = image.blurred();
    final magnitude = blurred.gradientMagnitude();
    final edgeMaps = [
      for (final percentile in config.edgePercentiles)
        _threshold(
          magnitude,
          math.max(config.minEdgeStrength, _percentile(magnitude, percentile)),
        ),
      // Canny-style thin edges keep faint cover borders that touch strong
      // ones, without the smooth background gradients a low threshold lets in.
      _canny(blurred, magnitude, config),
    ];
    final quads = <Quad>[];
    for (final raw in edgeMaps) {
      final edges = _dilate(raw, w, h);
      quads
        ..addAll(_quadsFromRegions(edges, edges, w, h).map((c) => c.quad))
        // Closed outlines filled in, with thin lines (table seams, cables,
        // neighbouring sleeves) that touch the cover removed by an opening.
        ..addAll(
          _quadsFromRegions(
            _open(_filledShapes(edges, w, h), w, h, config.openingRadius),
            edges,
            w,
            h,
          ).map((c) => c.quad),
        );
    }

    // Regions fail when a cover touches other edges (hands, clothes, a
    // crate), so also build outlines from straight lines, which tolerate
    // gaps where fingers cover a side.
    final gradients = Gradients.of(blurred);
    final canny = edgeMaps.last;
    final minSide = math.sqrt(config.minArea * w * h);
    final lines = houghLines(
      canny,
      gradients,
      minVotes: math.max(12, (0.35 * minSide).round()),
    );
    quads.addAll(quadsFromLines(lines, w, h, minSeparation: 0.8 * minSide));

    // Every candidate, whichever way it was found, is judged the same way.
    final support = Uint8List(w * h);
    final strong = edgeMaps[edgeMaps.length > 2 ? 1 : 0];
    for (var i = 0; i < support.length; i++) {
      support[i] = canny[i] | strong[i];
    }
    final priorQuads = [
      for (final p in priors) p.scale(w.toDouble(), h.toDouble()),
    ];
    final candidates = <_Candidate>[
      for (final quad in quads)
        ?_score(quad, support, gradients, priorQuads, w, h),
    ];
    return _suppress(candidates, priorQuads, blurred);
  }

  /// Checks shape and edge support of [quad] and scores it, or returns
  /// null when it does not look like a cover.
  _Candidate? _score(
    Quad quad,
    Uint8List edges,
    Gradients gradients,
    List<Quad> priors,
    int width,
    int height,
  ) {
    final area = quad.area;
    final frameArea = width * height.toDouble();
    if (area < config.minArea * frameArea ||
        area > config.maxArea * frameArea) {
      return null;
    }
    final aspect = quad.aspectRatio;
    if (aspect < config.minAspect || aspect > config.maxAspect) return null;
    if (quad.angles.any((a) => a < config.minAngle || a > config.maxAngle)) {
      return null;
    }
    // A side running along the frame edge is the end of the image, not the
    // edge of a sleeve: the sleeve is cut off there. It is judged on its
    // other three sides, which must then all be clear.
    var borderSides = 0;
    final sides = <double>[];
    final extensions = <double>[];
    for (var i = 0; i < 4; i++) {
      final a = quad.corners[i];
      final b = quad.corners[(i + 1) % 4];
      if (_alongFrameEdge(a, b, width, height)) {
        borderSides++;
        continue;
      }
      sides.add(orientedSupport(a, b, edges, gradients));
      // A sleeve's edge stops at its corners. Shelves, spines, table seams
      // and the like run on past them.
      final step = (b - a) * config.extensionLength;
      for (final (from, to) in [(b, b + step), (a, a - step)]) {
        // Past the frame edge there is nothing to see: measure what is left
        // in view, and skip ends too close to the edge to tell.
        final end = _clipToFrame(from, to, width, height);
        if (end.distanceTo(from) >= 4) {
          extensions.add(
            orientedSupport(from, end, edges, gradients, samples: 10),
          );
        }
      }
    }
    if (borderSides > 1) return null;
    final sorted = [...sides]..sort();
    final mean = sides.reduce((a, b) => a + b) / sides.length;
    if (borderSides == 1) {
      if (sorted[0] < config.minBorderCutSide ||
          mean < config.minOrientedMean) {
        return null;
      }
      // One side may be mostly hidden by a hand; the other three may not.
    } else if (sorted[1] < config.minOrientedSide ||
        mean < config.minOrientedMean) {
      return null;
    }
    final extended = extensions.isEmpty
        ? 0.0
        : extensions.reduce((a, b) => a + b) / extensions.length;
    // One or two corner ends may line up with a table edge or a
    // neighbouring sleeve; lines running on past three or more mean a shape
    // cut out of longer lines (a shelf, spines and a sleeve's top edge).
    final runOn = extensions.where((e) => e >= config.strongExtension).length;
    if (runOn >= 3 || extended > config.maxExtension) return null;
    // Covers are square: the further from 1:1, the less likely.
    final squareness =
        1 - 0.5 * (math.log(aspect).abs() / math.log(config.maxAspect));
    // Between an artwork frame and the sleeve around it, prefer the sleeve.
    final size = 0.8 + 0.2 * math.sqrt(area / frameArea);
    final fit = mean * squareness * size * (1 - extended);
    var quality = fit;
    for (final prior in priors) {
      final s = prior.sides;
      final side = (s[0] + s[1] + s[2] + s[3]) / 4;
      final distance = prior.meanCornerDistance(quad) / side;
      final closeness = 1 - distance / 0.12;
      if (closeness > 0) {
        quality = math.max(quality, fit * (1 + config.priorBonus * closeness));
      }
    }
    return _Candidate(
      quad,
      mean,
      quality,
      borderSides: borderSides,
      touchesBorder: _touchesBorder(quad, width, height),
    );
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
    final fill = hullArea <= 0
        ? 0.0
        : math.min(area, hullArea) / math.max(area, hullArea);
    if (fill < config.minFill) return null;
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
    return _Candidate(quad, mean, mean * fill);
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
    List<Quad> priors,
    GrayImage image,
  ) {
    final width = image.width;
    final height = image.height;
    // The same cover is usually found by several edge maps. Keep the
    // best-fitting outline of each near-duplicate group: a looser one may
    // have picked up a table seam along one side.
    candidates.sort((a, b) => b.quality.compareTo(a.quality));
    final distinct = <_Candidate>[];
    for (final candidate in candidates) {
      if (!distinct.any(
        (d) => d.quad.bounds.iou(candidate.quad.bounds) > 0.7,
      )) {
        distinct.add(candidate);
      }
    }
    candidates = distinct;

    // Best score first. Scores already prefer the sleeve over the artwork
    // inside it, and a tracked cover over a new shape around it.
    //
    // A shape sharing a side with a cover, on the far side of it, borrows
    // that cover's edge: a sleeve held below a face, with the wardrobe or
    // shelf behind, closes a square above it. Of the two, the one with
    // fewer sides along the frame edge is the cover; tracked covers count
    // too, for frames where the sleeve is missed.
    final tracked = [
      for (final p in priors)
        _Candidate(p, 0, 0, borderSides: _borderSides(p, width, height)),
    ];
    final kept = <_Candidate>[];
    for (final candidate in candidates) {
      if ([...kept, ...tracked].any(candidate.borrowsFrom)) continue;
      // Outlines built on this candidate's edge give way to it, whichever
      // was ranked first.
      final displaced = kept.where((k) => k.borrowsFrom(candidate)).toList();
      final overlaps = kept.any(
        (k) =>
            !displaced.contains(k) &&
            (k.quad.contains(candidate.quad.centroid) ||
                candidate.quad.contains(k.quad.centroid) ||
                // Sleeves side by side barely overlap; a shape sharing a large
                // part of a better one is built from its edges plus clutter.
                k.quad.bounds.overlapOfSmaller(candidate.quad.bounds) > 0.25),
      );
      if (overlaps) continue;
      // Shelves and crates full of records are squares too, but their
      // inside is rows of spines: straight lines running right across,
      // which artwork and lettering rarely are. Checked last, as it is the
      // slowest test.
      if (_spines(image, candidate.quad) >= config.maxSpines) continue;
      kept
        ..removeWhere(displaced.contains)
        ..add(candidate);
    }
    // Not capped inside the loop: a lower-ranked cover may still displace a
    // shape built on its edge.
    return [
      for (final k in kept.take(config.maxCovers))
        CoverDetection(
          k.quad.scale(1 / width, 1 / height),
          k.support,
          touchesBorder: k.touchesBorder,
        ),
    ];
  }
}

/// Points this close to the frame edge may hide a cut-off cover.
double _edgeMargin(int width, int height) => 0.015 * math.max(width, height);

bool _alongFrameEdge(Point2 a, Point2 b, int width, int height) {
  final margin = _edgeMargin(width, height);
  return (a.x <= margin && b.x <= margin) ||
      (a.x >= width - 1 - margin && b.x >= width - 1 - margin) ||
      (a.y <= margin && b.y <= margin) ||
      (a.y >= height - 1 - margin && b.y >= height - 1 - margin);
}

int _borderSides(Quad quad, int width, int height) {
  var count = 0;
  for (var i = 0; i < 4; i++) {
    final a = quad.corners[i];
    final b = quad.corners[(i + 1) % 4];
    if (_alongFrameEdge(a, b, width, height)) count++;
  }
  return count;
}

bool _touchesBorder(Quad quad, int width, int height) {
  final margin = _edgeMargin(width, height);
  return quad.corners.any(
    (c) =>
        c.x <= margin ||
        c.y <= margin ||
        c.x >= width - 1 - margin ||
        c.y >= height - 1 - margin,
  );
}

/// Whether a side of [a] lies along a side of [b], with the two quads on
/// opposite sides of it.
bool _sharesSide(Quad a, Quad b) {
  final ca = a.centroid;
  final cb = b.centroid;
  for (var i = 0; i < 4; i++) {
    final p = a.corners[i];
    final q = a.corners[(i + 1) % 4];
    final length = p.distanceTo(q);
    if (length == 0) continue;
    final ux = (q.x - p.x) / length;
    final uy = (q.y - p.y) / length;
    double across(Point2 r) => (r.x - p.x) * uy - (r.y - p.y) * ux;
    double along(Point2 r) => (r.x - p.x) * ux + (r.y - p.y) * uy;
    if (across(ca) * across(cb) >= 0) continue;
    final tolerance = math.max(3, 0.06 * length);
    for (var j = 0; j < 4; j++) {
      final r = b.corners[j];
      final s = b.corners[(j + 1) % 4];
      final ar = along(r);
      final as = along(s);
      if ((as - ar).abs() < 1) continue; // across the line, not along it
      final from = math.max(0.0, math.min(ar, as));
      final to = math.min(length, math.max(ar, as));
      if (to - from < 0.5 * math.min(length, r.distanceTo(s))) continue;
      // Compare the two sides where they overlap: a longer side of [b],
      // slightly tilted, may run off far from [a]'s line beyond the overlap.
      double gapAt(double t) {
        final f = (t - ar) / (as - ar);
        return across(r) + (across(s) - across(r)) * f;
      }

      if (gapAt(from).abs() <= tolerance && gapAt(to).abs() <= tolerance) {
        return true;
      }
    }
  }
  return false;
}

/// The share of the inside of [quad] crossed from side to side by straight
/// lines parallel to its sides, in whichever direction has more. The middle
/// 75 % of the outline is resampled to a square grid, so the measure does
/// not depend on the cover's size or tilt.
double _spines(GrayImage image, Quad quad) {
  const n = 48;
  final toImage = Homography.fromPoints(const [
    Point2(0, 0),
    Point2(1, 0),
    Point2(1, 1),
    Point2(0, 1),
  ], quad.corners);
  if (toImage == null) return 0;
  final grid = Float64List(n * n);
  final w = image.width;
  final h = image.height;
  final pixels = image.pixels;
  for (var row = 0; row < n; row++) {
    for (var col = 0; col < n; col++) {
      final p = toImage.apply(
        Point2(0.125 + 0.75 * col / (n - 1), 0.125 + 0.75 * row / (n - 1)),
      );
      final x = p.x.clamp(0.0, w - 1.001);
      final y = p.y.clamp(0.0, h - 1.001);
      final x0 = x.floor();
      final y0 = y.floor();
      final fx = x - x0;
      final fy = y - y0;
      final i = y0 * w + x0;
      final top = pixels[i] + (pixels[i + 1] - pixels[i]) * fx;
      final bottom = pixels[i + w] + (pixels[i + w + 1] - pixels[i + w]) * fx;
      grid[row * n + col] = top + (bottom - top) * fy;
    }
  }
  // Pixels on a strong edge of a vertical or a horizontal line (Sobel).
  final vertical = Uint8List(n * n);
  final horizontal = Uint8List(n * n);
  for (var y = 1; y < n - 1; y++) {
    for (var x = 1; x < n - 1; x++) {
      final i = y * n + x;
      final gx =
          (grid[i - n + 1] + 2 * grid[i + 1] + grid[i + n + 1]) -
          (grid[i - n - 1] + 2 * grid[i - 1] + grid[i + n - 1]);
      final gy =
          (grid[i + n - 1] + 2 * grid[i + n] + grid[i + n + 1]) -
          (grid[i - n - 1] + 2 * grid[i - n] + grid[i - n + 1]);
      if (gx * gx + gy * gy < 40 * 40) continue;
      if (gx.abs() > 2 * gy.abs()) vertical[i] = 1;
      if (gy.abs() > 2 * gx.abs()) horizontal[i] = 1;
    }
  }
  // A column (or row) is crossed by a line when, allowing a pixel of
  // wobble, most of it lies on such an edge.
  var columns = 0;
  var rows = 0;
  for (var a = 1; a < n - 1; a++) {
    var down = 0;
    var across = 0;
    for (var b = 1; b < n - 1; b++) {
      final v = b * n + a;
      if (vertical[v] | vertical[v - 1] | vertical[v + 1] != 0) down++;
      final hz = a * n + b;
      if (horizontal[hz] | horizontal[hz - n] | horizontal[hz + n] != 0) {
        across++;
      }
    }
    if (down > 0.6 * (n - 2)) columns++;
    if (across > 0.6 * (n - 2)) rows++;
  }
  return math.max(columns, rows) / (n - 2);
}

/// The point where the segment from [from] (inside the frame) to [to]
/// leaves the frame, or [to] when it stays inside.
Point2 _clipToFrame(Point2 from, Point2 to, int width, int height) {
  var t = 1.0;
  final d = to - from;
  void limit(double start, double delta, double max) {
    if (delta > 0 && start + delta > max) {
      t = math.min(t, (max - start) / delta);
    }
    if (delta < 0 && start + delta < 0) {
      t = math.min(t, -start / delta);
    }
  }

  limit(from.x, d.x, width - 1.0);
  limit(from.y, d.y, height - 1.0);
  return from + d * math.max(0, t);
}

class _Candidate {
  const _Candidate(
    this.quad,
    this.support,
    this.quality, {
    this.borderSides = 0,
    this.touchesBorder = false,
  });

  final Quad quad;
  final double support;

  /// Edge support times fill: how well the quad fits its region.
  final double quality;

  /// Sides lying along the frame edge, and whether a corner is near it.
  final int borderSides;
  final bool touchesBorder;

  /// Whether this outline is built on a side of [other], which has fewer
  /// sides along the frame edge. A corner merely near the edge does not
  /// count: a sleeve held close to the camera is whole but reaches it.
  bool borrowsFrom(_Candidate other) =>
      borderSides > other.borderSides && _sharesSide(quad, other.quad);
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

/// Canny edge map: non-maximum suppression along the gradient direction,
/// then hysteresis between a high and a low threshold.
Uint8List _canny(
  GrayImage blurred,
  Uint16List magnitude,
  CoverDetectorConfig config,
) {
  final width = blurred.width;
  final height = blurred.height;
  final p = blurred.pixels;
  final thin = Uint16List(magnitude.length);
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final i = y * width + x;
      final m = magnitude[i];
      if (m == 0) continue;
      final gx =
          (p[i - width + 1] + 2 * p[i + 1] + p[i + width + 1]) -
          (p[i - width - 1] + 2 * p[i - 1] + p[i + width - 1]);
      final gy =
          (p[i + width - 1] + 2 * p[i + width] + p[i + width + 1]) -
          (p[i - width - 1] + 2 * p[i - width] + p[i - width + 1]);
      // Neighbours across the edge, in one of four directions.
      final ax = gx.abs();
      final ay = gy.abs();
      int before;
      int after;
      if (ay * 5 < ax * 2) {
        before = i - 1;
        after = i + 1;
      } else if (ax * 5 < ay * 2) {
        before = i - width;
        after = i + width;
      } else if ((gx > 0) == (gy > 0)) {
        before = i - width - 1;
        after = i + width + 1;
      } else {
        before = i - width + 1;
        after = i + width - 1;
      }
      if (m >= magnitude[before] && m > magnitude[after]) thin[i] = m;
    }
  }

  final high = math.max(
    config.minEdgeStrength,
    _percentile(thin, config.cannyHighPercentile),
  );
  final low = math.max(
    config.minEdgeStrength ~/ 2,
    (high * config.cannyLowRatio).round(),
  );
  final edges = Uint8List(thin.length);
  final stack = Int32List(thin.length);
  var top = 0;
  for (var i = 0; i < thin.length; i++) {
    if (thin[i] >= high && edges[i] == 0) {
      edges[i] = 1;
      stack[top++] = i;
      while (top > 0) {
        final j = stack[--top];
        final x = j % width;
        final y = j ~/ width;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= height) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            if (nx < 0 || nx >= width) continue;
            final k = ny * width + nx;
            if (edges[k] == 0 && thin[k] >= low) {
              edges[k] = 1;
              stack[top++] = k;
            }
          }
        }
      }
    }
  }
  return edges;
}
