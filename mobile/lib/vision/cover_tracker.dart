import 'cover_detector.dart';
import 'geometry.dart';

/// A cover followed across frames.
class TrackedCover {
  TrackedCover._(this.id, this.quad, this.score, this.touchesBorder);

  /// Stable while the cover stays in view.
  final int id;

  /// Smoothed outline, normalised to the frame.
  Quad quad;
  double score;
  bool touchesBorder;

  /// Frames in which the cover was detected.
  int hits = 1;

  /// Consecutive frames without a detection.
  int misses = 0;

  /// How far the corners moved in the last frame, relative to the cover's
  /// size (0 = still).
  double motion = 0;

  /// Average side length in normalised units.
  double get size {
    final s = quad.sides;
    return (s[0] + s[1] + s[2] + s[3]) / 4;
  }

  bool get isVisible => misses == 0;
}

/// Matches detections to existing covers by overlap, smooths their corners,
/// and forgets covers that stay undetected for [maxMisses] frames.
class CoverTracker {
  CoverTracker({this.matchIou = 0.3, this.smoothing = 0.5, this.maxMisses = 3});

  /// Minimum bounding-box overlap to treat a detection as the same cover.
  final double matchIou;

  /// Weight of the new detection when smoothing corners (1 = no smoothing).
  final double smoothing;
  final int maxMisses;

  final List<TrackedCover> _tracks = [];
  int _nextId = 1;

  List<TrackedCover> get tracks => List.unmodifiable(_tracks);

  /// Covers seen in the latest frame.
  List<TrackedCover> get visible =>
      _tracks.where((t) => t.isVisible).toList(growable: false);

  /// Updates the tracks with one frame's detections.
  List<TrackedCover> update(List<CoverDetection> detections) {
    final unmatched = [...detections];
    final pairs = <(TrackedCover, CoverDetection, double)>[];
    for (final track in _tracks) {
      for (final detection in detections) {
        final iou = track.quad.bounds.iou(detection.quad.bounds);
        if (iou >= matchIou) pairs.add((track, detection, iou));
      }
    }
    pairs.sort((a, b) => b.$3.compareTo(a.$3));

    final updated = <TrackedCover>{};
    for (final (track, detection, _) in pairs) {
      if (updated.contains(track) || !unmatched.contains(detection)) continue;
      unmatched.remove(detection);
      updated.add(track);
      // Corners are always ordered from the top-left one, so they line up.
      final previous = track.quad;
      track
        ..quad = previous.lerp(detection.quad, smoothing)
        ..motion = previous.meanCornerDistance(detection.quad) / track.size
        ..score = detection.score
        ..touchesBorder = detection.touchesBorder
        ..hits += 1
        ..misses = 0;
    }

    for (final track in _tracks) {
      if (!updated.contains(track)) track.misses++;
    }
    _tracks.removeWhere((t) => t.misses > maxMisses);

    for (final detection in unmatched) {
      _tracks.add(
        TrackedCover._(
          _nextId++,
          detection.quad,
          detection.score,
          detection.touchesBorder,
        ),
      );
    }
    return visible;
  }

  void reset() => _tracks.clear();
}
