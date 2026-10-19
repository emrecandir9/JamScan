import 'dart:math' as math;

/// A point in image or normalised (0-1) coordinates.
class Point2 {
  const Point2(this.x, this.y);

  final double x;
  final double y;

  Point2 operator +(Point2 other) => Point2(x + other.x, y + other.y);
  Point2 operator -(Point2 other) => Point2(x - other.x, y - other.y);
  Point2 operator *(double factor) => Point2(x * factor, y * factor);

  double distanceTo(Point2 other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  bool operator ==(Object other) =>
      other is Point2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

/// Axis-aligned rectangle.
class Box {
  const Box(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get area => math.max(0, width) * math.max(0, height);

  double iou(Box other) {
    final overlap = Box(
      math.max(left, other.left),
      math.max(top, other.top),
      math.min(right, other.right),
      math.min(bottom, other.bottom),
    );
    if (overlap.width <= 0 || overlap.height <= 0) return 0;
    final shared = overlap.area;
    return shared / (area + other.area - shared);
  }
}

/// A convex quadrilateral with corners in clockwise order starting at the
/// top-left corner (in image coordinates, where y grows downwards).
class Quad {
  Quad(List<Point2> corners)
    : corners = List.unmodifiable(orderCorners(corners));

  final List<Point2> corners;

  Point2 get topLeft => corners[0];
  Point2 get topRight => corners[1];
  Point2 get bottomRight => corners[2];
  Point2 get bottomLeft => corners[3];

  double get area => polygonArea(corners);

  Point2 get centroid {
    var x = 0.0;
    var y = 0.0;
    for (final c in corners) {
      x += c.x;
      y += c.y;
    }
    return Point2(x / 4, y / 4);
  }

  Box get bounds {
    final xs = corners.map((c) => c.x);
    final ys = corners.map((c) => c.y);
    return Box(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }

  /// Side lengths: top, right, bottom, left.
  List<double> get sides => [
    for (var i = 0; i < 4; i++) corners[i].distanceTo(corners[(i + 1) % 4]),
  ];

  /// Width over height, averaging opposite sides.
  double get aspectRatio {
    final s = sides;
    final height = (s[1] + s[3]) / 2;
    return height == 0 ? 0 : ((s[0] + s[2]) / 2) / height;
  }

  /// Interior angles in degrees, one per corner.
  List<double> get angles => [
    for (var i = 0; i < 4; i++)
      _angleAt(corners[(i + 3) % 4], corners[i], corners[(i + 1) % 4]),
  ];

  bool contains(Point2 point) => pointInPolygon(point, corners);

  Quad scale(double sx, double sy) =>
      Quad([for (final c in corners) Point2(c.x * sx, c.y * sy)]);

  Quad map(Point2 Function(Point2) transform) =>
      Quad([for (final c in corners) transform(c)]);

  /// Linear blend towards [other]; `t = 1` returns [other].
  Quad lerp(Quad other, double t) => Quad([
    for (var i = 0; i < 4; i++)
      corners[i] + (other.corners[i] - corners[i]) * t,
  ]);

  /// Mean corner distance to [other].
  double meanCornerDistance(Quad other) {
    var total = 0.0;
    for (var i = 0; i < 4; i++) {
      total += corners[i].distanceTo(other.corners[i]);
    }
    return total / 4;
  }

  @override
  String toString() => 'Quad$corners';
}

double _angleAt(Point2 previous, Point2 corner, Point2 next) {
  final a = previous - corner;
  final b = next - corner;
  final cos =
      (a.x * b.x + a.y * b.y) /
      math.max(
        1e-12,
        math.sqrt(a.x * a.x + a.y * a.y) * math.sqrt(b.x * b.x + b.y * b.y),
      );
  return math.acos(cos.clamp(-1.0, 1.0)) * 180 / math.pi;
}

/// Orders four corners clockwise (in screen space), starting top-left.
List<Point2> orderCorners(List<Point2> points) {
  assert(points.length == 4, 'A quad needs four corners.');
  var cx = 0.0;
  var cy = 0.0;
  for (final p in points) {
    cx += p.x;
    cy += p.y;
  }
  cx /= 4;
  cy /= 4;
  final sorted = [...points]
    ..sort(
      (a, b) => math
          .atan2(a.y - cy, a.x - cx)
          .compareTo(math.atan2(b.y - cy, b.x - cx)),
    );
  // atan2 order with y down is clockwise on screen. Start at the corner
  // with the smallest x + y, which is the top-left one.
  var start = 0;
  for (var i = 1; i < 4; i++) {
    if (sorted[i].x + sorted[i].y < sorted[start].x + sorted[start].y) {
      start = i;
    }
  }
  return [for (var i = 0; i < 4; i++) sorted[(start + i) % 4]];
}

/// Absolute area of a simple polygon (shoelace formula).
double polygonArea(List<Point2> points) {
  var sum = 0.0;
  for (var i = 0; i < points.length; i++) {
    final a = points[i];
    final b = points[(i + 1) % points.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum.abs() / 2;
}

bool pointInPolygon(Point2 point, List<Point2> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i];
    final b = polygon[j];
    if ((a.y > point.y) != (b.y > point.y) &&
        point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

/// Convex hull (Andrew's monotone chain), counter-clockwise in maths
/// orientation, without collinear points.
List<Point2> convexHull(List<Point2> points) {
  if (points.length < 3) return [...points];
  final sorted = [...points]
    ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  double cross(Point2 o, Point2 a, Point2 b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

  final lower = <Point2>[];
  for (final p in sorted) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <Point2>[];
  for (final p in sorted.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  return [
    ...lower.sublist(0, lower.length - 1),
    ...upper.sublist(0, upper.length - 1),
  ];
}

/// Approximates a convex polygon by four of its vertices, repeatedly
/// dropping the vertex whose removal loses the least area. Returns `null`
/// when [hull] has fewer than four vertices.
List<Point2>? reduceToQuadrilateral(List<Point2> hull) {
  if (hull.length < 4) return null;
  final points = [...hull];
  while (points.length > 4) {
    var best = 0;
    var bestLoss = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final a = points[(i - 1 + points.length) % points.length];
      final b = points[i];
      final c = points[(i + 1) % points.length];
      final loss = polygonArea([a, b, c]);
      if (loss < bestLoss) {
        bestLoss = loss;
        best = i;
      }
    }
    points.removeAt(best);
  }
  return points;
}
