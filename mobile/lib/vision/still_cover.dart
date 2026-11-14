import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'cover_crop.dart';
import 'cover_detector.dart';
import 'frame_quality.dart';
import 'geometry.dart';
import 'gray_image.dart';

/// A photo or gallery image turned into a recognition-ready cover crop.
class PreparedCover {
  const PreparedCover({
    required this.jpeg,
    required this.hash,
    required this.quality,
    required this.detected,
  });

  /// Upright, flattened [cropSide] x [cropSide] JPEG.
  final Uint8List jpeg;
  final int hash;
  final CoverQuality quality;

  /// False when no cover outline was found and the centre of the photo
  /// was used instead.
  final bool detected;
}

/// Thrown when the bytes are not a readable image.
class UnreadableImageException implements Exception {
  const UnreadableImageException();
}

/// Same steps as the live stream, for a single still image (manual shutter
/// or gallery import): find the most prominent cover, flatten it, and
/// measure its quality. Without an outline, the centre square of the photo
/// is used, as the user framed the cover there.
PreparedCover prepareStillCover(
  Uint8List bytes, {
  CoverDetector detector = const CoverDetector(),
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const UnreadableImageException();
  final photo = img.bakeOrientation(decoded);

  final scale = 320 / math.max(photo.width, photo.height);
  final small = scale < 1
      ? img.copyResize(
          photo,
          width: (photo.width * scale).round(),
          height: (photo.height * scale).round(),
          interpolation: img.Interpolation.average,
        )
      : photo;
  final grey = GrayImage(small.width, small.height);
  for (var y = 0; y < small.height; y++) {
    for (var x = 0; x < small.width; x++) {
      grey.pixels[y * small.width + x] = small.getPixel(x, y).luminance.toInt();
    }
  }

  final found = detector.detect(grey).where((d) => !d.touchesBorder).toList()
    ..sort((a, b) => b.quad.area.compareTo(a.quad.area));
  final quad = found.isNotEmpty ? found.first.quad : _centreSquare(photo);
  final crop = flattenCover(ImageSource(photo), quad);
  return PreparedCover(
    jpeg: encodeCrop(crop),
    hash: differenceHash(crop),
    quality: measureCoverQuality(grey, quad),
    detected: found.isNotEmpty,
  );
}

/// The largest centred square covering 90 % of the shorter side,
/// normalised to the image.
Quad _centreSquare(img.Image photo) {
  final side = 0.9 * math.min(photo.width, photo.height);
  final w = side / photo.width;
  final h = side / photo.height;
  final left = (1 - w) / 2;
  final top = (1 - h) / 2;
  return Quad([
    Point2(left, top),
    Point2(left + w, top),
    Point2(left + w, top + h),
    Point2(left, top + h),
  ]);
}
