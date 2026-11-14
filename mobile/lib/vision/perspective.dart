import 'geometry.dart';

/// A 3 x 3 projective transform, stored row-major with `h[8] == 1`.
class Homography {
  const Homography(this.h);

  final List<double> h;

  /// The transform that maps each of [from] onto the matching point of [to].
  ///
  /// Solves the standard eight-unknown linear system; returns `null` when the
  /// points are degenerate (three of them collinear).
  static Homography? fromPoints(List<Point2> from, List<Point2> to) {
    assert(from.length == 4 && to.length == 4, 'Four point pairs needed.');
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final x = from[i].x;
      final y = from[i].y;
      final u = to[i].x;
      final v = to[i].y;
      a[2 * i]
        ..[0] = x
        ..[1] = y
        ..[2] = 1
        ..[6] = -u * x
        ..[7] = -u * y
        ..[8] = u;
      a[2 * i + 1]
        ..[3] = x
        ..[4] = y
        ..[5] = 1
        ..[6] = -v * x
        ..[7] = -v * y
        ..[8] = v;
    }
    final solution = _solve(a);
    return solution == null ? null : Homography([...solution, 1]);
  }

  Point2 apply(Point2 p) {
    final w = h[6] * p.x + h[7] * p.y + h[8];
    return Point2(
      (h[0] * p.x + h[1] * p.y + h[2]) / w,
      (h[3] * p.x + h[4] * p.y + h[5]) / w,
    );
  }
}

/// Gaussian elimination with partial pivoting on an 8 x 9 augmented matrix.
List<double>? _solve(List<List<double>> a) {
  const n = 8;
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var row = col + 1; row < n; row++) {
      if (a[row][col].abs() > a[pivot][col].abs()) pivot = row;
    }
    if (a[pivot][col].abs() < 1e-12) return null;
    final swap = a[col];
    a[col] = a[pivot];
    a[pivot] = swap;
    for (var row = 0; row < n; row++) {
      if (row == col) continue;
      final factor = a[row][col] / a[col][col];
      if (factor == 0) continue;
      for (var k = col; k <= n; k++) {
        a[row][k] -= factor * a[col][k];
      }
    }
  }
  return [for (var i = 0; i < n; i++) a[i][n] / a[i][i]];
}
