import 'dart:math' as math;
import 'dart:typed_data';

/// An 8-bit single-channel image stored row by row without padding.
class GrayImage {
  GrayImage(this.width, this.height, [Uint8List? pixels])
    : pixels = pixels ?? Uint8List(width * height) {
    assert(this.pixels.length == width * height, 'Pixel count mismatch.');
  }

  final int width;
  final int height;
  final Uint8List pixels;

  int at(int x, int y) => pixels[y * width + x];

  /// Average-pools a luma plane (for example the camera's Y plane, whose
  /// rows may be padded to [rowStride] bytes) so its longer side is at most
  /// [maxSide] pixels.
  factory GrayImage.fromLuma(
    Uint8List luma, {
    required int width,
    required int height,
    int? rowStride,
    int maxSide = 320,
  }) {
    final stride = rowStride ?? width;
    final factor = math.max(1, (math.max(width, height) / maxSide).ceil());
    final outWidth = width ~/ factor;
    final outHeight = height ~/ factor;
    final out = Uint8List(outWidth * outHeight);
    final count = factor * factor;
    for (var oy = 0; oy < outHeight; oy++) {
      final y0 = oy * factor;
      for (var ox = 0; ox < outWidth; ox++) {
        final x0 = ox * factor;
        var sum = 0;
        for (var dy = 0; dy < factor; dy++) {
          final row = (y0 + dy) * stride + x0;
          for (var dx = 0; dx < factor; dx++) {
            sum += luma[row + dx];
          }
        }
        out[oy * outWidth + ox] = sum ~/ count;
      }
    }
    return GrayImage(outWidth, outHeight, out);
  }

  /// 5 x 5 Gaussian blur (binomial kernel 1 4 6 4 1), separable.
  GrayImage blurred() {
    final temp = Uint16List(width * height);
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        temp[row + x] =
            pixels[row + _clamp(x - 2, width)] +
            4 * pixels[row + _clamp(x - 1, width)] +
            6 * pixels[row + x] +
            4 * pixels[row + _clamp(x + 1, width)] +
            pixels[row + _clamp(x + 2, width)];
      }
    }
    final out = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      final r0 = _clamp(y - 2, height) * width;
      final r1 = _clamp(y - 1, height) * width;
      final r2 = y * width;
      final r3 = _clamp(y + 1, height) * width;
      final r4 = _clamp(y + 2, height) * width;
      for (var x = 0; x < width; x++) {
        final sum =
            temp[r0 + x] +
            4 * temp[r1 + x] +
            6 * temp[r2 + x] +
            4 * temp[r3 + x] +
            temp[r4 + x];
        out[r2 + x] = (sum + 128) >> 8;
      }
    }
    return GrayImage(width, height, out);
  }

  /// Sobel gradient magnitude `|gx| + |gy|` (0-2040); borders are 0.
  Uint16List gradientMagnitude() {
    final out = Uint16List(width * height);
    for (var y = 1; y < height - 1; y++) {
      final up = (y - 1) * width;
      final mid = y * width;
      final down = (y + 1) * width;
      for (var x = 1; x < width - 1; x++) {
        final gx =
            (pixels[up + x + 1] +
                2 * pixels[mid + x + 1] +
                pixels[down + x + 1]) -
            (pixels[up + x - 1] +
                2 * pixels[mid + x - 1] +
                pixels[down + x - 1]);
        final gy =
            (pixels[down + x - 1] +
                2 * pixels[down + x] +
                pixels[down + x + 1]) -
            (pixels[up + x - 1] + 2 * pixels[up + x] + pixels[up + x + 1]);
        out[mid + x] = gx.abs() + gy.abs();
      }
    }
    return out;
  }
}

int _clamp(int value, int length) =>
    value < 0 ? 0 : (value >= length ? length - 1 : value);
