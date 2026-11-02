import 'dart:typed_data';

import 'camera_frame.dart';
import 'cover_crop.dart';
import 'cover_tracker.dart';
import 'frame_quality.dart';
import 'geometry.dart';
import 'gray_image.dart';

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

/// Watches each tracked cover over several frames, remembers its best view,
/// and captures it once (FR-04): as soon as the cover has been seen for
/// [minHits] frames, is still, and its best view scores [goodScore]; or
/// after [maxHits] frames if its best view at least reaches [minScore].
/// A cover is captured only once while it stays tracked (no repeated
/// submissions of the same visible album).
class BestFrameSelector {
  BestFrameSelector({
    this.minHits = 3,
    this.maxHits = 12,
    this.goodScore = 0.5,
    this.minScore = 0.2,
    this.maxMotion = 0.03,
  });

  final int minHits;
  final int maxHits;
  final double goodScore;
  final double minScore;
  final double maxMotion;

  final Map<int, _Best> _best = {};
  final Set<int> _captured = {};

  /// Whether the cover with [trackId] has already been captured.
  bool isCaptured(int trackId) => _captured.contains(trackId);

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
    _best.removeWhere((id, _) => !alive.contains(id));
    _captured.removeWhere((id) => !alive.contains(id));
    latest.clear();

    final captures = <CoverCapture>[];
    for (final track in visible) {
      if (track.touchesBorder) continue;
      final quality = measureCoverQuality(
        grey,
        track.quad,
        motion: track.motion,
      );
      latest[track.id] = quality;
      if (_captured.contains(track.id)) continue;

      final best = _best[track.id];
      if (best == null || quality.score > best.quality.score) {
        _best[track.id] = _Best(quality, frame, track.quad);
      }
      final chosen = _best[track.id]!;
      final ready =
          track.hits >= minHits &&
          track.motion <= maxMotion &&
          chosen.quality.score >= goodScore;
      final waitedLongEnough =
          track.hits >= maxHits && chosen.quality.score >= minScore;
      if (!ready && !waitedLongEnough) continue;

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
      _captured.add(track.id);
      _best.remove(track.id);
    }
    return captures;
  }

  void reset() {
    _best.clear();
    _captured.clear();
    latest.clear();
  }
}
