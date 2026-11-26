import 'dart:math' as math;
import 'dart:typed_data';

import 'camera_frame.dart';
import 'cover_crop.dart';
import 'cover_tracker.dart';
import 'frame_quality.dart';
import 'geometry.dart';
import 'gray_image.dart';
import 'perspective.dart';

/// A cover image picked from the live stream, ready for recognition.
class CoverCapture {
  const CoverCapture({
    required this.trackId,
    required this.jpeg,
    required this.hash,
    required this.quality,
  });

  /// The tracked cover it came from.
  final int trackId;

  /// Upright, flattened [cropSide] x [cropSide] JPEG.
  final Uint8List jpeg;

  /// [differenceHash] of the crop, to spot the same cover again.
  final int hash;
  final CoverQuality quality;
}

class _Best {
  _Best(this.quality, this.frame, this.quad);

  final CoverQuality quality;
  final CameraFrame frame;
  final Quad quad;
}

/// What the selector knows about one tracked cover.
class _Watch {
  /// Frames since the cover appeared, or since it was swapped for another.
  int seen = 0;

  /// [coverSignature] in the previous frame, and for how many frames in a
  /// row it barely changed.
  int? signature;
  int steadyFrames = 0;

  /// Signature when the cover was captured, and for how many frames in a
  /// row the cover has looked different since.
  int? capturedSignature;
  int changedFrames = 0;

  _Best? best;

  bool get captured => capturedSignature != null;
}

/// Watches each tracked cover over several frames, remembers its best view,
/// and captures it once (FR-04): as soon as the cover has been seen for
/// [minHits] frames, is still, and its best view scores [goodScore]; or
/// after [maxHits] frames if its best view at least reaches [minScore].
/// Both need the artwork itself to look the same for [minStillFrames]
/// frames, so a sleeve being pulled out or slid in front is not captured.
///
/// A cover is captured only once while it stays tracked (no repeated
/// submissions of the same visible album), unless the artwork inside the
/// outline changes for good: someone put a different record in the same
/// spot, which is then watched and captured like a new cover.
class BestFrameSelector {
  BestFrameSelector({
    this.minHits = 3,
    this.maxHits = 12,
    this.goodScore = 0.5,
    this.minScore = 0.2,
    this.maxMotion = 0.03,
    this.minStillFrames = 2,
    this.steadyBits = 12,
    this.changeBits = 18,
    this.changeFrames = 2,
  });

  final int minHits;
  final int maxHits;
  final double goodScore;
  final double minScore;
  final double maxMotion;

  /// Consecutive frames in which both the outline and the artwork must stay
  /// put before a capture.
  final int minStillFrames;

  /// Largest change of [coverSignature] between frames that counts as the
  /// same, steady artwork.
  final int steadyBits;

  /// Bits of [coverSignature] that must differ from the captured view, in
  /// [changeFrames] consecutive frames, before a captured cover is taken to
  /// be a different sleeve.
  final int changeBits;
  final int changeFrames;

  final Map<int, _Watch> _watches = {};

  /// Whether the cover with [trackId] has already been captured.
  bool isCaptured(int trackId) => _watches[trackId]?.captured ?? false;

  /// The latest quality of each visible cover, by track id.
  final Map<int, CoverQuality> latest = {};

  /// Updates with one analysed frame and returns the covers to capture now.
  List<CoverCapture> update({
    required CameraFrame frame,
    required GrayImage grey,
    required List<TrackedCover> visible,
    required Iterable<int> trackedIds,
  }) {
    final alive = trackedIds.toSet();
    _watches.removeWhere((id, _) => !alive.contains(id));
    // Keep the last hint of a cover kept on screen through a missed frame.
    latest.removeWhere((id, _) => !alive.contains(id));
    // A cover not usable in this frame (missed, or cut off by the frame
    // edge) must show steady artwork again from scratch when it is back.
    final usable = {
      for (final t in visible)
        if (!t.touchesBorder) t.id,
    };
    for (final entry in _watches.entries) {
      if (!usable.contains(entry.key)) {
        entry.value
          ..signature = null
          ..steadyFrames = 0;
      }
    }

    final captures = <CoverCapture>[];
    for (final track in visible) {
      if (track.touchesBorder) {
        latest.remove(track.id);
        continue;
      }
      // A cover reaches the selector once the tracker shows it, already
      // seen in earlier frames (counted up to the [minHits] wait, so frames
      // spent cut off by the frame edge do not count towards [maxHits]).
      final watch = _watches.putIfAbsent(
        track.id,
        () => _Watch()..seen = math.min(track.hits - 1, minHits - 1),
      );
      final quality = measureCoverQuality(
        grey,
        track.quad,
        motion: track.motion,
      );
      latest[track.id] = quality;

      final signatures = coverSignatures(grey, track.quad);
      final signature = signatures.first;
      final previous = watch.signature;
      final unchanged =
          previous != null &&
          signatureDistance(previous, signatures) <= steadyBits;
      watch
        ..signature = signature
        ..steadyFrames = unchanged ? watch.steadyFrames + 1 : 0
        ..seen += 1;
      // The best view must show the artwork now in the outline, not the
      // sleeve that was there before it changed.
      if (!unchanged) watch.best = null;

      final captured = watch.capturedSignature;
      if (captured != null) {
        if (signatureDistance(captured, signatures) <= changeBits) {
          watch.changedFrames = 0;
          continue;
        }
        // Only steady new artwork counts: a hand or glare passing over the
        // same sleeve keeps changing.
        watch.changedFrames = watch.steadyFrames > 0
            ? watch.changedFrames + 1
            : 0;
        if (watch.changedFrames < changeFrames) continue;
        // A different sleeve: start over.
        watch
          ..capturedSignature = null
          ..changedFrames = 0
          ..seen = 1
          ..best = null;
      }

      final best = watch.best;
      if (best == null || quality.score > best.quality.score) {
        watch.best = _Best(quality, frame, track.quad);
      }
      final chosen = watch.best!;
      // steadyFrames counts unchanged steps between views, one fewer than
      // the views themselves.
      final steady = watch.steadyFrames >= minStillFrames - 1;
      final ready =
          watch.seen >= minHits &&
          track.motion <= maxMotion &&
          track.stillFrames >= minStillFrames &&
          chosen.quality.score >= goodScore;
      final waitedLongEnough =
          watch.seen >= maxHits && chosen.quality.score >= minScore;
      if (!steady || (!ready && !waitedLongEnough)) continue;

      final crop = flattenCover(
        CameraFrameSource(chosen.frame),
        chosen.quad,
        sensorDegrees: chosen.frame.rotationDegrees,
      );
      captures.add(
        CoverCapture(
          trackId: track.id,
          jpeg: encodeCrop(crop),
          hash: differenceHash(crop),
          quality: chosen.quality,
        ),
      );
      watch
        ..capturedSignature = signature
        ..best = null;
    }
    return captures;
  }

  void reset() {
    _watches.clear();
    latest.clear();
  }
}

/// [coverSignature] read from each of the four corners as the top-left
/// one, first as given: near a 45-degree tilt the corner order of an outline
/// can rotate between frames.
List<int> coverSignatures(GrayImage grey, Quad quad) => [
  for (var r = 0; r < 4; r++) coverSignature(grey, quad, rotation: r),
];

/// Smallest [hammingDistance] between [signature] and any of [rotations].
int signatureDistance(int signature, List<int> rotations) =>
    rotations.map((r) => hammingDistance(signature, r)).reduce(math.min);

/// 64-bit difference hash of the cover inside [quad] (normalised corners),
/// read from the analysis frame: cheap enough for every frame. [rotation]
/// starts the corners that many places further round.
int coverSignature(GrayImage grey, Quad quad, {int rotation = 0}) {
  final corners = [
    for (var i = 0; i < 4; i++)
      Point2(
        quad.corners[(i + rotation) % 4].x * grey.width,
        quad.corners[(i + rotation) % 4].y * grey.height,
      ),
  ];
  final h = Homography.fromPoints(const [
    Point2(0, 0),
    Point2(1, 0),
    Point2(1, 1),
    Point2(0, 1),
  ], corners);
  if (h == null) return 0;
  final cells = List<int>.filled(9 * 8, 0);
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 9; x++) {
      var sum = 0;
      // Average a 3 x 3 grid inside each cell.
      for (var sy = 0; sy < 3; sy++) {
        for (var sx = 0; sx < 3; sx++) {
          final p = h.apply(
            Point2(
              0.05 + 0.9 * (x + (sx + 0.5) / 3) / 9,
              0.05 + 0.9 * (y + (sy + 0.5) / 3) / 8,
            ),
          );
          final px = p.x.round().clamp(0, grey.width - 1);
          final py = p.y.round().clamp(0, grey.height - 1);
          sum += grey.at(px, py);
        }
      }
      cells[y * 9 + x] = sum;
    }
  }
  var hash = 0;
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      hash <<= 1;
      if (cells[y * 9 + x] < cells[y * 9 + x + 1]) hash |= 1;
    }
  }
  return hash;
}
