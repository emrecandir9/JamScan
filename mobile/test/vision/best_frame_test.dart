import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jamscan/vision/camera_frame.dart';
import 'package:jamscan/vision/cover_crop.dart';
import 'package:jamscan/vision/frame_analyzer.dart';
import 'package:jamscan/vision/frame_quality.dart';
import 'package:jamscan/vision/geometry.dart';
import 'package:jamscan/vision/gray_image.dart';
import 'package:jamscan/vision/still_cover.dart';

import 'scene.dart';

/// Upright artwork: bright band along the top, textured below, so a crop's
/// orientation can be checked.
int bandArtwork(double u, double v) {
  if (v < 0.25) return 225;
  return ((u * 8).floor() + (v * 8).floor()).isEven ? 35 : 95;
}

/// A greyscale frame as a camera frame with neutral chroma.
CameraFrame toFrame(GrayImage grey, {int rotation = 0}) {
  final chroma = Uint8List((grey.width ~/ 2) * (grey.height ~/ 2))
    ..fillRange(0, (grey.width ~/ 2) * (grey.height ~/ 2), 128);
  return CameraFrame(
    width: grey.width,
    height: grey.height,
    y: grey.pixels,
    yRowStride: grey.width,
    u: chroma,
    v: chroma,
    uvRowStride: grey.width ~/ 2,
    uvPixelStride: 1,
    rotationDegrees: rotation,
  );
}

GrayImage coverScene({double left = 90, Artwork artwork = bandArtwork}) {
  return renderScene(
    width: 320,
    height: 240,
    covers: [PlacedCover(square(left, 50, 140), artwork)],
  );
}

/// Mean grey level of rows [from, to) of a crop.
double rowMean(img.Image crop, int from, int to) {
  var sum = 0.0;
  for (var y = from; y < to; y++) {
    for (var x = 0; x < crop.width; x++) {
      sum += crop.getPixel(x, y).luminance;
    }
  }
  return sum / ((to - from) * crop.width);
}

void main() {
  group('cover quality', () {
    test('blur, darkness and motion lower the score', () {
      final sharp = coverScene();
      final quad = square(90, 50, 140).let320x240();
      final blurred = sharp.blurred().blurred().blurred();
      final dark = GrayImage(
        320,
        240,
        Uint8List.fromList([for (final p in sharp.pixels) p ~/ 6]),
      );

      final good = measureCoverQuality(sharp, quad);
      final soft = measureCoverQuality(blurred, quad);
      final dim = measureCoverQuality(dark, quad);
      final shaky = measureCoverQuality(sharp, quad, motion: 0.06);

      expect(good.score, greaterThan(0.5));
      expect(good.hint, isNull);
      expect(soft.score, lessThan(good.score));
      expect(soft.sharpness, lessThan(good.sharpness / 4));
      expect(dim.hint, CaptureHint.tooDark);
      expect(shaky.hint, CaptureHint.holdSteady);
      expect(shaky.score, lessThan(good.score / 2));
    });
  });

  group('best-frame selection', () {
    test('captures a still, sharp cover once, after three frames', () {
      final analyzer = FrameAnalyzer();
      final frame = toFrame(coverScene());

      final results = [for (var i = 0; i < 6; i++) analyzer.analyze(frame)];

      expect(results.map((r) => r.captures.length), [0, 0, 1, 0, 0, 0]);
      expect(results.last.covers.single.captured, isTrue);
      final capture = results[2].captures.single;
      final crop = img.decodeJpg(capture.jpeg)!;
      expect(crop.width, cropSide);
      expect(crop.height, cropSide);
    });

    test('waits while the cover moves', () {
      final analyzer = FrameAnalyzer();
      final moving = [
        for (var i = 0; i < 5; i++) toFrame(coverScene(left: 60.0 + 12 * i)),
      ];

      final whileMoving = moving.map(analyzer.analyze).toList();
      // Corner smoothing settles within a few frames once the cover stops.
      final still = [for (var i = 0; i < 4; i++) analyzer.analyze(moving.last)];

      expect(whileMoving.expand((r) => r.captures), isEmpty);
      expect(whileMoving.last.covers.single.hint, CaptureHint.holdSteady);
      expect(still.expand((r) => r.captures), hasLength(1));
    });

    test('sends the sharpest view seen so far', () {
      final analyzer = FrameAnalyzer();
      final sharp = coverScene();
      final soft = sharp.blurred().blurred();

      analyzer.analyze(toFrame(soft));
      analyzer.analyze(toFrame(sharp));
      final third = analyzer.analyze(toFrame(soft));

      final sharpQuality = measureCoverQuality(
        sharp,
        square(90, 50, 140).let320x240(),
      );
      expect(third.captures, hasLength(1));
      expect(
        third.captures.single.quality.sharpness,
        greaterThan(sharpQuality.sharpness * 0.5),
      );
    });

    test('never captures a blurry cover', () {
      final analyzer = FrameAnalyzer();
      var soft = coverScene();
      for (var i = 0; i < 4; i++) {
        soft = soft.blurred();
      }
      final frame = toFrame(soft);

      final results = [for (var i = 0; i < 15; i++) analyzer.analyze(frame)];

      expect(results.expand((r) => r.captures), isEmpty);
      expect(results.last.covers.single.hint, CaptureHint.blurry);
    });

    test('never captures a cover cut off by the frame edge', () {
      final analyzer = FrameAnalyzer();
      final frame = toFrame(
        renderScene(
          width: 320,
          height: 240,
          // Plain artwork: the textured half of bandArtwork is square
          // enough to be found as a cover of its own.
          covers: [PlacedCover(square(-30, 50, 150), darkArtwork)],
        ),
      );

      final results = [for (var i = 0; i < 15; i++) analyzer.analyze(frame)];

      expect(results.expand((r) => r.captures), isEmpty);
    });
  });

  group('cover crop', () {
    test('flattens a tilted cover the right way up', () {
      const corners = [
        Point2(70, 40),
        Point2(230, 60),
        Point2(220, 210),
        Point2(80, 200),
      ];
      final scene = renderScene(
        width: 320,
        height: 240,
        covers: [PlacedCover(corners, bandArtwork)],
        clutter: false,
      );

      final crop = flattenCover(
        CameraFrameSource(toFrame(scene)),
        Quad(corners).scale(1 / 320, 1 / 240),
      );

      expect(rowMean(crop, 10, 100), greaterThan(190));
      expect(rowMean(crop, 200, 500), lessThan(90));
    });

    test('turns a sideways sensor frame upright', () {
      // On a 90-degree sensor, the upright top of the cover is the frame's
      // left side.
      int sideways(double u, double v) => bandArtwork(1 - v, u);
      final scene = renderScene(
        width: 320,
        height: 240,
        covers: [PlacedCover(square(90, 50, 140), sideways)],
        clutter: false,
      );

      final crop = flattenCover(
        CameraFrameSource(toFrame(scene, rotation: 90)),
        square(90, 50, 140).let320x240(),
        sensorDegrees: 90,
      );

      expect(rowMean(crop, 10, 100), greaterThan(190));
      expect(rowMean(crop, 200, 500), lessThan(90));
    });

    test('the same cover gives nearly the same hash; others differ', () {
      img.Image cropOf(Artwork artwork, List<Point2> corners, int seed) {
        final scene = renderScene(
          width: 320,
          height: 240,
          covers: [PlacedCover(corners, artwork)],
          seed: seed,
        );
        return flattenCover(
          CameraFrameSource(toFrame(scene)),
          Quad(corners).scale(1 / 320, 1 / 240),
        );
      }

      const tilted = [
        Point2(84, 46),
        Point2(232, 56),
        Point2(226, 194),
        Point2(88, 190),
      ];
      final a = differenceHash(cropOf(bandArtwork, square(90, 50, 140), 1));
      final b = differenceHash(cropOf(bandArtwork, tilted, 2));
      final c = differenceHash(cropOf(darkArtwork, square(90, 50, 140), 1));
      final d = differenceHash(cropOf(framedArtwork, square(90, 50, 140), 1));

      expect(hammingDistance(a, b), lessThanOrEqualTo(10));
      expect(hammingDistance(a, c), greaterThan(16));
      expect(hammingDistance(a, d), greaterThan(16));
    });
  });

  group('still photos', () {
    test('finds and flattens the cover in a photo', () {
      final scene = renderScene(
        width: 640,
        height: 480,
        covers: [
          PlacedCover(const [
            Point2(150, 90),
            Point2(470, 120),
            Point2(450, 420),
            Point2(170, 400),
          ], bandArtwork),
        ],
      );
      final photo = img.Image(width: 640, height: 480);
      for (var y = 0; y < 480; y++) {
        for (var x = 0; x < 640; x++) {
          final v = scene.at(x, y);
          photo.setPixelRgb(x, y, v, v, v);
        }
      }

      final prepared = prepareStillCover(img.encodeJpg(photo, quality: 92));
      final crop = img.decodeJpg(prepared.jpeg)!;

      expect(prepared.detected, isTrue);
      expect(rowMean(crop, 10, 100), greaterThan(180));
      expect(rowMean(crop, 200, 500), lessThan(100));
    });

    test('falls back to the centre without an outline', () {
      final flat = img.Image(width: 400, height: 300);
      img.fill(flat, color: img.ColorRgb8(120, 120, 120));

      final prepared = prepareStillCover(img.encodePng(flat));

      expect(prepared.detected, isFalse);
      expect(img.decodeJpg(prepared.jpeg)!.width, cropSide);
    });

    test('rejects bytes that are not an image', () {
      expect(
        () => prepareStillCover(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<UnreadableImageException>()),
      );
    });
  });
}

extension on List<Point2> {
  /// Pixel corners in a 320 x 240 frame, normalised.
  Quad let320x240() => Quad(this).scale(1 / 320, 1 / 240);
}
