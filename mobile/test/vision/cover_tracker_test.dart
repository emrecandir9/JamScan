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
    test('shows a cover only once it was found in two frames', () {
      final tracker = CoverTracker();

      expect(tracker.update([at(0.2, 0.2)]), isEmpty);
      final shown = tracker.update([at(0.2, 0.2)]).single;

      expect(shown.hits, 2);
      expect(tracker.tracks, hasLength(1));
    });

    test('keeps the same id while a cover moves a little', () {
      final tracker = CoverTracker(minHitsToShow: 1);

      final first = tracker.update([at(0.2, 0.2)]).single;
      final second = tracker.update([at(0.204, 0.202)]).single;

      expect(second.id, first.id);
      expect(second.motion, greaterThan(0));
      // Small movements are mostly noise: the outline follows only part of
      // the way.
      expect(second.quad.topLeft.x, greaterThan(0.2));
      expect(second.quad.topLeft.x, lessThan(0.203));
    });

    test('follows a large movement at once', () {
      final tracker = CoverTracker(minHitsToShow: 1);
      tracker.update([at(0.2, 0.2)]);

      final moved = tracker.update([at(0.25, 0.22)]).single;

      expect(moved.quad.topLeft.x, closeTo(0.25, 1e-9));
    });

    test('gives separate covers separate ids', () {
      final tracker = CoverTracker(minHitsToShow: 1);

      final covers = tracker.update([at(0.05, 0.3), at(0.6, 0.3)]);

      expect(covers.map((c) => c.id).toSet(), hasLength(2));
    });

    test('keeps showing a cover through short gaps, then forgets it', () {
      final tracker = CoverTracker(coastFrames: 2, maxMisses: 3);
      tracker
        ..update([at(0.2, 0.2)])
        ..update([at(0.2, 0.2)]);
      final id = tracker.visible.single.id;

      tracker
        ..update([])
        ..update([]);
      expect(tracker.visible.single.id, id);
      expect(tracker.detected, isEmpty);

      expect(tracker.update([at(0.2, 0.2)]).single.id, id);

      tracker
        ..update([])
        ..update([])
        ..update([]);
      expect(tracker.visible, isEmpty);
      tracker.update([]);
      expect(tracker.tracks, isEmpty);
    });

    test('a much bigger shape in the same place is a different cover', () {
      final tracker = CoverTracker(minHitsToShow: 1);
      final small = tracker.update([at(0.3, 0.3, 0.2)]).single;

      final big = tracker.update([at(0.25, 0.25, 0.4)]);

      expect(big.map((c) => c.id), isNot(contains(small.id)));
    });

    test('a confirmed cover replaces the outline it overlaps', () {
      final tracker = CoverTracker();
      tracker
        ..update([at(0.3, 0.3, 0.2)])
        ..update([at(0.3, 0.3, 0.2)]);
      final old = tracker.visible.single.id;

      // The sleeve is swapped for a bigger one in the same spot.
      tracker
        ..update([at(0.25, 0.25, 0.4)])
        ..update([at(0.25, 0.25, 0.4)]);

      expect(tracker.visible.single.id, isNot(old));
      expect(tracker.tracks.map((t) => t.id), isNot(contains(old)));
    });

    test('a still cover reports no motion', () {
      final tracker = CoverTracker(minHitsToShow: 1);
      tracker.update([at(0.3, 0.3)]);

      final still = tracker.update([at(0.3, 0.3)]).single;

      expect(still.motion, 0);
      expect(still.stillFrames, 1);
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

    test('corner pairing survives a change of top-left corner', () {
      // A diamond: a little jitter changes which corner sorts first.
      final a = Quad(const [
        Point2(0.5, 0),
        Point2(1, 0.5),
        Point2(0.5, 1),
        Point2(0.02, 0.5),
      ]);
      final b = Quad(const [
        Point2(0.5, 0.03),
        Point2(1, 0.5),
        Point2(0.5, 1),
        Point2(0, 0.5),
      ]);
      expect(a.topLeft, const Point2(0.5, 0));
      expect(b.topLeft, const Point2(0, 0.5));

      expect(a.meanCornerDistance(b), lessThan(0.02));
      final halfway = a.lerp(b, 0.5);
      expect(halfway.area, closeTo(a.area, 0.02));
    });

    test('a square with a clipped corner reduces to the full square', () {
      // Hull of a cover whose bottom-right corner is missing from the
      // outline.
      const pentagon = [
        Point2(0, 0),
        Point2(100, 0),
        Point2(100, 85),
        Point2(85, 100),
        Point2(0, 100),
      ];

      final quad = Quad(reduceToQuadrilateral(pentagon)!);

      expect(quad.bottomRight.x, closeTo(100, 1e-9));
      expect(quad.bottomRight.y, closeTo(100, 1e-9));
    });

    test('a large missing area is not invented', () {
      // Half of the square is missing: dropping a vertex is cheaper than
      // inventing a big corner.
      const shape = [
        Point2(0, 0),
        Point2(100, 0),
        Point2(100, 30),
        Point2(30, 100),
        Point2(0, 100),
      ];

      final quad = Quad(reduceToQuadrilateral(shape)!);

      expect(quad.area, lessThan(100 * 100 * 0.9));
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
