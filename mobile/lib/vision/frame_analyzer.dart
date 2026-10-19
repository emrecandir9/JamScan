import 'camera_frame.dart';
import 'cover_detector.dart';
import 'cover_tracker.dart';
import 'geometry.dart';
import 'gray_image.dart';

/// A tracked cover as reported to the UI. The quad is normalised to the
/// camera frame in sensor orientation.
class CoverSnapshot {
  const CoverSnapshot({
    required this.id,
    required this.quad,
    required this.touchesBorder,
  });

  final int id;
  final Quad quad;
  final bool touchesBorder;
}

/// The result of analysing one frame.
class FrameAnalysis {
  const FrameAnalysis({required this.covers, required this.elapsedMs});

  final List<CoverSnapshot> covers;
  final int elapsedMs;
}

/// Runs detection and tracking on camera frames. Pure Dart, so it can live
/// in a background isolate and be tested without a device.
class FrameAnalyzer {
  FrameAnalyzer({
    this.detector = const CoverDetector(),
    CoverTracker? tracker,
    this.analysisSide = 320,
  }) : _tracker = tracker ?? CoverTracker();

  final CoverDetector detector;
  final CoverTracker _tracker;

  /// Longer side of the downscaled frame used for detection.
  final int analysisSide;

  FrameAnalysis analyze(CameraFrame frame) {
    final watch = Stopwatch()..start();
    final grey = GrayImage.fromLuma(
      frame.y,
      width: frame.width,
      height: frame.height,
      rowStride: frame.yRowStride,
      maxSide: analysisSide,
    );
    final covers = _tracker.update(detector.detect(grey));
    return FrameAnalysis(
      covers: [
        for (final c in covers)
          CoverSnapshot(id: c.id, quad: c.quad, touchesBorder: c.touchesBorder),
      ],
      elapsedMs: watch.elapsedMilliseconds,
    );
  }

  void reset() => _tracker.reset();
}
