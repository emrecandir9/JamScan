import 'dart:math' as math;

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

  /// Consecutive frames in which the cover barely moved.
  int stillFrames = 0;

  /// Average side length in normalised units.
  double get size {
    final s = quad.sides;
    return (s[0] + s[1] + s[2] + s[3]) / 4;
  }

  /// Detected in the latest frame.
  bool get isDetected => misses == 0;
}

/// Matches detections to existing covers by overlap and smooths their
/// corners, so the outline on screen is steady:
///
/// - a cover is shown only once it was detected in [minHitsToShow] frames,
///   so a shape seen in a single frame never flashes up;
/// - a shown cover stays on screen through up to [coastFrames] missed
///   frames, and is forgotten after [maxMisses];
/// - small corner movements (detection noise) are smoothed strongly, large
///   ones (the cover really moved) are followed at once;
/// - a detection much bigger or smaller than the tracked outline is a
///   different shape, not the same cover, and starts its own track.
class CoverTracker {
  CoverTracker({
    this.matchIou = 0.3,
    this.maxAreaChange = 1.6,
    this.minHitsToShow = 2,
    this.coastFrames = 2,
    this.maxMisses = 3,
    this.minSmoothing = 0.35,
    this.fastMotion = 0.06,
    this.stillMotion = 0.03,
  });

  /// Minimum bounding-box overlap to treat a detection as the same cover.
  final double matchIou;

  /// Largest area ratio between a track and a detection that still match.
  final double maxAreaChange;
  final int minHitsToShow;
  final int coastFrames;
  final int maxMisses;

  /// Weight of a new detection that barely moved (1 = no smoothing). The
  /// weight rises to 1 as the movement approaches [fastMotion].
  final double minSmoothing;
  final double fastMotion;

  /// Movement, relative to the cover's size, below which a frame counts as
  /// still.
  final double stillMotion;

  final List<TrackedCover> _tracks = [];
  int _nextId = 1;

  List<TrackedCover> get tracks => List.unmodifiable(_tracks);

  /// Covers to show: confirmed, and detected recently.
  List<TrackedCover> get visible => _tracks
      .where((t) => t.hits >= minHitsToShow && t.misses <= coastFrames)
      .toList(growable: false);

  /// Shown covers that were detected in the latest frame, so their outline
  /// matches the current image.
  List<TrackedCover> get detected =>
      visible.where((t) => t.isDetected).toList(growable: false);

  /// Updates the tracks with one frame's detections and returns the covers
  /// to show.
  List<TrackedCover> update(List<CoverDetection> detections) {
    final unmatched = [...detections];
    final pairs = <(TrackedCover, CoverDetection, double)>[];
    for (final track in _tracks) {
      final area = track.quad.area;
      for (final detection in detections) {
        final ratio = detection.quad.area / math.max(area, 1e-9);
        if (ratio > maxAreaChange || ratio < 1 / maxAreaChange) continue;
        final iou = track.quad.bounds.iou(detection.quad.bounds);
        if (iou < matchIou) continue;
        // A shown cover keeps its detection over a shape seen only once.
        final confirmed = track.hits >= minHitsToShow;
        pairs.add((track, detection, iou + (confirmed ? 0.1 : 0)));
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
      final motion = previous.meanCornerDistance(detection.quad) / track.size;
      final weight =
          minSmoothing +
          (1 - minSmoothing) *
              ((motion - 0.01) / (fastMotion - 0.01)).clamp(0.0, 1.0);
      track
        ..quad = previous.lerp(detection.quad, weight)
        ..motion = motion
        ..stillFrames = motion <= stillMotion ? track.stillFrames + 1 : 0
        ..score = detection.score
        ..touchesBorder = detection.touchesBorder
        ..hits += 1
        ..misses = 0;
    }

    for (final track in _tracks) {
      if (!updated.contains(track)) {
        track
          ..misses += 1
          ..stillFrames = 0;
      }
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

    // A confirmed cover replaces lingering outlines it overlaps (the old
    // shape of the same sleeve, or the previous sleeve in the same place).
    final current = detected;
    _tracks.removeWhere(
      (t) =>
          !t.isDetected &&
          current.any(
            (c) => c.quad.bounds.overlapOfSmaller(t.quad.bounds) > 0.5,
          ),
    );
    return visible;
  }

  void reset() => _tracks.clear();
}
