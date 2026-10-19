import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/vision/cover_detector.dart';
import 'package:jamscan/vision/cover_tracker.dart';
import 'package:jamscan/vision/geometry.dart';
import 'package:jamscan/vision/perspective.dart';

CoverDetection at(double left, double top, [double side = 0.3]) {
  return CoverDetection(
    Quad([
      Point2(left, top),
      Point2(left + side, top),
      Point2(left + side, top + side),
      Point2(left, top + side),
    ]),
    0.9,
  );
}

void main() {
  group('CoverTracker', () {
    test('keeps the same id while a cover moves a little', () {
      final tracker = CoverTracker();

      final first = tracker.update([at(0.2, 0.2)]).single;
      final second = tracker.update([at(0.22, 0.21)]).single;

      expect(second.id, first.id);
      expect(second.hits, 2);
      expect(second.motion, greaterThan(0));
      // Smoothed halfway between the two detections.
      expect(second.quad.topLeft.x, closeTo(0.21, 1e-9));
    });

    test('gives separate covers separate ids', () {
      final tracker = CoverTracker();

      final covers = tracker.update([at(0.05, 0.3), at(0.6, 0.3)]);

      expect(covers.map((c) => c.id).toSet(), hasLength(2));
    });

    test('tolerates a few missed frames, then forgets the cover', () {
      final tracker = CoverTracker(maxMisses: 2);
      final id = tracker.update([at(0.2, 0.2)]).single.id;

      tracker.update([]);
      tracker.update([]);
      expect(tracker.tracks.single.id, id);
      expect(tracker.visible, isEmpty);

      final back = tracker.update([at(0.2, 0.2)]).single;
      expect(back.id, id);

      tracker
        ..update([])
        ..update([])
        ..update([]);
      expect(tracker.tracks, isEmpty);
      expect(tracker.update([at(0.2, 0.2)]).single.id, isNot(id));
    });

    test('a still cover reports no motion', () {
      final tracker = CoverTracker();
      tracker.update([at(0.3, 0.3)]);

      final still = tracker.update([at(0.3, 0.3)]).single;

      expect(still.motion, 0);
    });
  });

  group('geometry', () {
    test('orders corners clockwise from the top-left', () {
      final quad = Quad(const [
        Point2(1, 1),
        Point2(0, 0),
        Point2(0, 1),
        Point2(1, 0),
      ]);

      expect(quad.corners, const [
        Point2(0, 0),
        Point2(1, 0),
        Point2(1, 1),
        Point2(0, 1),
      ]);
      expect(quad.area, 1);
      expect(quad.angles, everyElement(closeTo(90, 1e-9)));
    });

    test('homography maps a tilted quad onto the unit square', () {
      const tilted = [
        Point2(10, 20),
        Point2(110, 30),
        Point2(100, 140),
        Point2(5, 120),
      ];
      const unit = [Point2(0, 0), Point2(1, 0), Point2(1, 1), Point2(0, 1)];

      final h = Homography.fromPoints(tilted, unit)!;

      for (var i = 0; i < 4; i++) {
        final p = h.apply(tilted[i]);
        expect(p.x, closeTo(unit[i].x, 1e-9));
        expect(p.y, closeTo(unit[i].y, 1e-9));
      }
      expect(
        Homography.fromPoints(const [
          Point2(0, 0),
          Point2(1, 1),
          Point2(2, 2),
          Point2(0, 1),
        ], unit),
        isNull,
      );
    });
  });
}
