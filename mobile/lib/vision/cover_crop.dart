import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'camera_frame.dart';
import 'geometry.dart';
import 'perspective.dart';

/// Anything colour pixels can be sampled from.
abstract interface class PixelSource {
  int get width;
  int get height;

  /// Red, green and blue (0-255) at an integer pixel inside the image.
  (int, int, int) rgbAt(int x, int y);
}

/// A camera frame as a [PixelSource], in sensor orientation.
class CameraFrameSource implements PixelSource {
  const CameraFrameSource(this.frame);

  final CameraFrame frame;

  @override
  int get width => frame.width;
  @override
  int get height => frame.height;
  @override
  (int, int, int) rgbAt(int x, int y) => frame.rgbAt(x, y);
}

/// A decoded still image (photo or gallery import) as a [PixelSource].
class ImageSource implements PixelSource {
  const ImageSource(this.image);

  final img.Image image;

  @override
  int get width => image.width;
  @override
  int get height => image.height;
  @override
  (int, int, int) rgbAt(int x, int y) {
    final p = image.getPixel(x, y);
    return (p.r.toInt(), p.g.toInt(), p.b.toInt());
  }
}

/// Side of the square cover crops sent for recognition.
const cropSide = 512;

/// Flattens the cover inside [quad] (normalised to [source], in sensor
/// orientation) into an upright [side] x [side] image.
///
/// [sensorDegrees] turns the crop so the cover reads the right way up on
/// screen; still images are already upright and use 0.
img.Image flattenCover(
  PixelSource source,
  Quad quad, {
  int sensorDegrees = 0,
  int side = cropSide,
}) {
  // Order the corners as they appear upright on screen, then map them back
  // to source pixels.
  final upright = Quad([
    for (final c in quad.corners) sensorToUpright(c, sensorDegrees),
  ]);
  final corners = [
    for (final c in upright.corners) _uprightToSensor(c, sensorDegrees),
  ].map((p) => Point2(p.x * source.width, p.y * source.height)).toList();
  final toSource = Homography.fromPoints([
    const Point2(0, 0),
    Point2(side.toDouble(), 0),
    Point2(side.toDouble(), side.toDouble()),
    Point2(0, side.toDouble()),
  ], corners)!;

  final out = img.Image(width: side, height: side);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final p = toSource.apply(Point2(x + 0.5, y + 0.5));
      final sx = p.x.floor().clamp(0, source.width - 1);
      final sy = p.y.floor().clamp(0, source.height - 1);
      final (r, g, b) = source.rgbAt(sx, sy);
      out.setPixelRgb(x, y, r, g, b);
    }
  }
  return out;
}

/// Inverse of [sensorToUpright].
Point2 _uprightToSensor(Point2 p, int sensorDegrees) {
  return switch (sensorDegrees % 360) {
    90 => Point2(p.y, 1 - p.x),
    180 => Point2(1 - p.x, 1 - p.y),
    270 => Point2(1 - p.y, p.x),
    _ => p,
  };
}

/// JPEG bytes for upload.
Uint8List encodeCrop(img.Image crop) => img.encodeJpg(crop, quality: 90);

/// 64-bit difference hash: compares neighbouring pixels of a 9 x 8
/// greyscale thumbnail. Two photos of the same cover differ in only a few
/// bits.
int differenceHash(img.Image image) {
  final small = img.copyResize(
    img.grayscale(img.Image.from(image)),
    width: 9,
    height: 8,
    interpolation: img.Interpolation.average,
  );
  var hash = 0;
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      hash <<= 1;
      if (small.getPixel(x, y).r < small.getPixel(x + 1, y).r) hash |= 1;
    }
  }
  return hash;
}

/// Number of differing bits between two [differenceHash] values.
int hammingDistance(int a, int b) {
  var x = a ^ b;
  var count = 0;
  while (x != 0) {
    x &= x - 1;
    count++;
  }
  return count;
}
