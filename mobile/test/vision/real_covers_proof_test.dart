import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jamscan/vision/cover_detector.dart';
import 'package:jamscan/vision/geometry.dart';
import 'package:jamscan/vision/gray_image.dart';

import 'scene.dart';

/// Development covers fetched by the backend's `scripts.fetch_dev_covers`.
/// They are copyrighted and not in Git, so this test only runs locally.
final coversDir = Directory('../backend/data/dev/images');
final proofDir = Directory('build/vision_proof');

void main() {
  test(
    'detects real album covers placed at random angles',
    () {
      final files = coversDir.listSync().whereType<File>().where((f) {
        return f.path.endsWith('.jpg');
      }).toList()..sort((a, b) => a.path.compareTo(b.path));
      proofDir.createSync(recursive: true);
      final random = math.Random(42);
      const detector = CoverDetector();
      const width = 640;
      const height = 480;

      var detected = 0;
      var total = 0;
      final errors = <double>[];
      for (final (index, file) in files.indexed) {
        final cover = img.decodeImage(file.readAsBytesSync())!;
        final grey = img.grayscale(cover);
        int artwork(double u, double v) {
          final x = (u * (grey.width - 1)).round();
          final y = (v * (grey.height - 1)).round();
          return grey.getPixel(x, y).r.toInt();
        }

        // Two scenes per cover: cluttered table and a plain wall.
        for (final clutter in [true, false]) {
          total++;
          final truth = randomQuad(random, width, height);
          final camera = renderScene(
            width: width,
            height: height,
            covers: [PlacedCover(truth, artwork)],
            seed: index * 2 + (clutter ? 1 : 0),
            clutter: clutter,
            background: clutter ? null : (x, y) => 150 + (x * 40 ~/ width),
          );
          // Same path as the live camera: downscale the luma plane first.
          final frame = GrayImage.fromLuma(
            camera.pixels,
            width: width,
            height: height,
          );
          final found = detector.detect(frame);
          final error = bestError(found, truth, width, height);
          final hit = error != null && error < 0.05;
          if (hit) {
            detected++;
            errors.add(error);
          }
          if (index < 6) {
            saveProof(
              camera,
              found,
              truth,
              '${index}_${clutter ? 't' : 'w'}',
              hit,
            );
          }
        }
      }

      // False positives: empty tables and walls must stay empty.
      var phantom = 0;
      for (var seed = 0; seed < 40; seed++) {
        final empty = renderScene(
          width: width,
          height: height,
          covers: [],
          seed: 1000 + seed,
          clutter: seed.isEven,
        );
        phantom += detector
            .detect(
              GrayImage.fromLuma(empty.pixels, width: width, height: height),
            )
            .length;
      }

      errors.sort();
      final rate = detected / total;
      final median = errors.isEmpty ? double.nan : errors[errors.length ~/ 2];
      // ignore: avoid_print
      print(
        'Real covers: $detected/$total detected '
        '(${(rate * 100).toStringAsFixed(1)}%), median corner error '
        '${(median * 100).toStringAsFixed(2)}% of frame width. '
        'Phantom covers in 40 empty scenes: $phantom. '
        'Annotated samples in ${proofDir.path}/',
      );
      expect(rate, greaterThan(0.8));
      expect(phantom, 0);
    },
    skip: coversDir.existsSync()
        ? false
        : 'Run backend scripts.fetch_dev_covers to enable this test.',
  );
}

/// A cover filling 35-75 % of the frame height, tilted and in perspective.
List<Point2> randomQuad(math.Random random, int width, int height) {
  final side = height * (0.35 + random.nextDouble() * 0.4);
  final cx = width * (0.3 + random.nextDouble() * 0.4);
  final cy = height * (0.35 + random.nextDouble() * 0.3);
  final angle = (random.nextDouble() * 2 - 1) * 15 * math.pi / 180;
  final jitter = side * 0.08;
  return [
    for (final (dx, dy) in [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)])
      Point2(
        cx +
            (dx * math.cos(angle) - dy * math.sin(angle)) * side +
            (random.nextDouble() * 2 - 1) * jitter,
        cy +
            (dx * math.sin(angle) + dy * math.cos(angle)) * side +
            (random.nextDouble() * 2 - 1) * jitter,
      ),
  ];
}

double? bestError(
  List<CoverDetection> found,
  List<Point2> truth,
  int width,
  int height,
) {
  final expected = Quad(truth);
  double? best;
  for (final detection in found) {
    final quad = detection.quad.scale(width.toDouble(), height.toDouble());
    var worst = 0.0;
    for (var i = 0; i < 4; i++) {
      worst = math.max(worst, quad.corners[i].distanceTo(expected.corners[i]));
    }
    final error = worst / width;
    if (best == null || error < best) best = error;
  }
  return best;
}

void saveProof(
  GrayImage frame,
  List<CoverDetection> found,
  List<Point2> truth,
  String name,
  bool hit,
) {
  final out = img.Image(width: frame.width, height: frame.height);
  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      final v = frame.at(x, y);
      out.setPixelRgb(x, y, v, v, v);
    }
  }
  void drawQuad(Quad quad, img.Color colour) {
    for (var i = 0; i < 4; i++) {
      final a = quad.corners[i];
      final b = quad.corners[(i + 1) % 4];
      img.drawLine(
        out,
        x1: a.x.round(),
        y1: a.y.round(),
        x2: b.x.round(),
        y2: b.y.round(),
        color: colour,
        thickness: 3,
      );
    }
  }

  drawQuad(Quad(truth), img.ColorRgb8(0, 120, 255));
  for (final d in found) {
    drawQuad(
      d.quad.scale(frame.width.toDouble(), frame.height.toDouble()),
      img.ColorRgb8(0, 230, 60),
    );
  }
  File('${proofDir.path}/detect_${name}_${hit ? 'ok' : 'miss'}.png')
      .writeAsBytesSync(img.encodePng(out));
}
