import 'dart:math' as math;

import 'geometry.dart';
import 'gray_image.dart';

/// How usable one view of a cover is for recognition.
class CoverQuality {
  const CoverQuality({
    required this.sharpness,
    required this.brightness,
    required this.highlights,
    required this.glare,
    required this.size,
    required this.skew,
    required this.motion,
  });

  /// Variance of the Laplacian inside the cover (higher is sharper).
  final double sharpness;

  /// Mean grey level inside the cover, 0-255.
  final double brightness;

  /// Grey level of the brightest 5 % of the cover. Low only when the photo
  /// itself is dark: a black sleeve still has light lettering or artwork.
  final double highlights;

  /// Fraction of nearly white pixels (reflections on the sleeve).
  final double glare;

  /// Cover area as a fraction of the frame.
  final double size;

  /// Largest corner-angle deviation from 90 degrees (perspective).
  final double skew;

  /// Corner movement since the previous frame, relative to cover size.
  final double motion;

  /// Combined score from 0 (unusable) to 1 (ideal).
  double get score =>
      _ramp(sharpness, 20, 160) *
      _ramp(highlights, 30, 90) *
      (1 - _ramp(brightness, 215, 245)) *
      (1 - _ramp(glare, 0.05, 0.4)) *
      _ramp(size, 0.04, 0.15) *
      (1 - _ramp(skew, 15, 40)) *
      (1 - _ramp(motion, 0.01, 0.08));

  /// What the user could fix, or `null` when nothing stands out.
  CaptureHint? get hint {
    if (motion > 0.04) return CaptureHint.holdSteady;
    if (highlights < 60) return CaptureHint.tooDark;
    if (glare > 0.2) return CaptureHint.glare;
    if (sharpness < 30) return CaptureHint.blurry;
    if (size < 0.08) return CaptureHint.moveCloser;
    return null;
  }

  @override
  String toString() =>
      'CoverQuality(score ${score.toStringAsFixed(2)}, sharp '
      '${sharpness.toStringAsFixed(0)}, bright ${brightness.toStringAsFixed(0)}, '
      'highlights ${highlights.toStringAsFixed(0)}, '
      'glare ${glare.toStringAsFixed(2)}, size ${size.toStringAsFixed(2)}, '
      'skew ${skew.toStringAsFixed(0)}, motion ${motion.toStringAsFixed(3)})';
}

enum CaptureHint { holdSteady, tooDark, glare, blurry, moveCloser }

/// 0 below [low], 1 above [high], linear in between.
double _ramp(double value, double low, double high) =>
    ((value - low) / (high - low)).clamp(0.0, 1.0);

/// Measures [quad] (normalised to [image]) in an analysis frame.
CoverQuality measureCoverQuality(
  GrayImage image,
  Quad quad, {
  double motion = 0,
}) {
  final pixels = quad.scale(image.width.toDouble(), image.height.toDouble());
  final box = pixels.bounds;
  final x0 = math.max(1, box.left.ceil());
  final y0 = math.max(1, box.top.ceil());
  final x1 = math.min(image.width - 2, box.right.floor());
  final y1 = math.min(image.height - 2, box.bottom.floor());
  // Measure inside the cover, away from its border, so the edge between
  // sleeve and background does not count as sharpness.
  final inner = pixels.lerp(
    Quad([for (var i = 0; i < 4; i++) pixels.centroid]),
    0.1,
  );

  var count = 0;
  var sum = 0.0;
  final histogram = List<int>.filled(256, 0);
  var bright = 0;
  var lapSum = 0.0;
  var lapSquares = 0.0;
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      if (!inner.contains(Point2(x + 0.5, y + 0.5))) continue;
      final v = image.at(x, y);
      final lap =
          (image.at(x - 1, y) +
                  image.at(x + 1, y) +
                  image.at(x, y - 1) +
                  image.at(x, y + 1) -
                  4 * v)
              .toDouble();
      count++;
      sum += v;
      histogram[v]++;
      if (v >= 245) bright++;
      lapSum += lap;
      lapSquares += lap * lap;
    }
  }
  if (count == 0) {
    return CoverQuality(
      sharpness: 0,
      brightness: 0,
      highlights: 0,
      glare: 0,
      size: 0,
      skew: 90,
      motion: motion,
    );
  }
  final lapMean = lapSum / count;
  var seen = 0;
  var highlights = 255;
  for (var level = 255; level >= 0; level--) {
    seen += histogram[level];
    if (seen >= count * 0.05) {
      highlights = level;
      break;
    }
  }
  return CoverQuality(
    sharpness: lapSquares / count - lapMean * lapMean,
    brightness: sum / count,
    highlights: highlights.toDouble(),
    glare: bright / count,
    size: quad.area,
    skew: quad.angles.map((a) => (a - 90).abs()).reduce(math.max),
    motion: motion,
  );
}
