import 'best_frame_selector.dart';
import 'camera_frame.dart';
import 'cover_detector.dart';
import 'cover_tracker.dart';
import 'frame_quality.dart';
import 'geometry.dart';
import 'gray_image.dart';

/// A tracked cover as reported to the UI. The quad is normalised to the
/// camera frame in sensor orientation.
class CoverSnapshot {
  const CoverSnapshot({
    required this.id,
    required this.quad,
    required this.touchesBorder,
    this.captured = false,
    this.hint,
  });

  final int id;
  final Quad quad;
  final bool touchesBorder;

  /// True once a view of this cover was sent for recognition.
  final bool captured;

  /// What would help capture this cover, if anything.
  final CaptureHint? hint;
}

/// The result of analysing one frame.
class FrameAnalysis {
  const FrameAnalysis({
    required this.covers,
    required this.elapsedMs,
    this.captures = const [],
  });

  final List<CoverSnapshot> covers;
  final int elapsedMs;

  /// Covers picked for recognition in this frame (S2-10).
  final List<CoverCapture> captures;
}

/// Runs detection, tracking and best-frame selection on camera frames. Pure Dart, so it can live
/// in a background isolate and be tested without a device.
class FrameAnalyzer {
  FrameAnalyzer({
    this.detector = const CoverDetector(),
    CoverTracker? tracker,
    BestFrameSelector? selector,
    this.analysisSide = 320,
  }) : _tracker = tracker ?? CoverTracker(),
       _selector = selector ?? BestFrameSelector();

  final CoverDetector detector;
  final CoverTracker _tracker;
  final BestFrameSelector _selector;

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
    final captures = _selector.update(
      frame: frame,
      grey: grey,
      visible: covers,
      trackedIds: _tracker.tracks.map((t) => t.id),
    );
    return FrameAnalysis(
      covers: [
        for (final c in covers)
          CoverSnapshot(
            id: c.id,
            quad: c.quad,
            touchesBorder: c.touchesBorder,
            captured: _selector.isCaptured(c.id),
            hint: _selector.latest[c.id]?.hint,
          ),
      ],
      captures: captures,
      elapsedMs: watch.elapsedMilliseconds,
    );
  }

  void reset() {
    _tracker.reset();
    _selector.reset();
  }
}
