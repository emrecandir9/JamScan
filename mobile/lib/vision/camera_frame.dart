import 'dart:typed_data';

import 'geometry.dart';

/// A YUV 4:2:0 camera frame copied out of the camera plugin, so it can be
/// sent to a background isolate. Coordinates are in sensor orientation.
class CameraFrame {
  const CameraFrame({
    required this.width,
    required this.height,
    required this.y,
    required this.yRowStride,
    required this.u,
    required this.v,
    required this.uvRowStride,
    required this.uvPixelStride,
  });

  final int width;
  final int height;
  final Uint8List y;
  final int yRowStride;
  final Uint8List u;
  final Uint8List v;
  final int uvRowStride;

  /// 1 for planar (I420) and 2 for interleaved (NV12/NV21) chroma.
  final int uvPixelStride;

  int lumaAt(int x, int yy) => y[yy * yRowStride + x];

  /// RGB at a pixel, using the BT.601 conversion Android cameras use.
  (int, int, int) rgbAt(int x, int yy) {
    final luma = y[yy * yRowStride + x];
    final uvIndex = (yy >> 1) * uvRowStride + (x >> 1) * uvPixelStride;
    final cb = u[uvIndex] - 128;
    final cr = v[uvIndex] - 128;
    final r = luma + 1.402 * cr;
    final g = luma - 0.344136 * cb - 0.714136 * cr;
    final b = luma + 1.772 * cb;
    return (_byte(r), _byte(g), _byte(b));
  }
}

int _byte(double value) => value < 0 ? 0 : (value > 255 ? 255 : value.round());

/// Maps a normalised point from the camera sensor's orientation to the
/// upright (portrait) preview the user sees. [sensorDegrees] is the
/// camera's `sensorOrientation` (90 on most phone back cameras).
Point2 sensorToUpright(Point2 p, int sensorDegrees) {
  return switch (sensorDegrees % 360) {
    90 => Point2(1 - p.y, p.x),
    180 => Point2(1 - p.x, 1 - p.y),
    270 => Point2(p.y, 1 - p.x),
    _ => p,
  };
}

/// Where a normalised point of an upright preview with aspect ratio
/// [previewAspect] (width / height) lands in a view of [viewWidth] x
/// [viewHeight] that shows the preview with `BoxFit.cover`.
Point2 previewToView(
  Point2 p, {
  required double previewAspect,
  required double viewWidth,
  required double viewHeight,
}) {
  final viewAspect = viewWidth / viewHeight;
  double shownWidth;
  double shownHeight;
  if (previewAspect > viewAspect) {
    shownHeight = viewHeight;
    shownWidth = viewHeight * previewAspect;
  } else {
    shownWidth = viewWidth;
    shownHeight = viewWidth / previewAspect;
  }
  return Point2(
    (viewWidth - shownWidth) / 2 + p.x * shownWidth,
    (viewHeight - shownHeight) / 2 + p.y * shownHeight,
  );
}
