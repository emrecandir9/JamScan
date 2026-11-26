import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/vision/camera_frame.dart';
import 'package:jamscan/vision/frame_analyzer.dart';
import 'package:jamscan/vision/geometry.dart';

/// Replays recorded videos through the live pipeline (detection, tracking,
/// best-frame capture) and reports how steady and plausible the outlines
/// are. Frames come from `backend/scripts/prepare_replay_frames.py`; videos
/// are not committed, so this test only runs locally.
///
/// Results go to `build/replay_out/<label>/`, where `<label>` is
/// `JAMSCAN_REPLAY_LABEL` (default `current`), for before/after comparison.
final replayDir = Directory(
  Platform.environment['JAMSCAN_REPLAY_DIR'] ?? 'build/replay',
);

void main() {
  test(
    'replays recorded clips through the live pipeline',
    () {
      final label = Platform.environment['JAMSCAN_REPLAY_LABEL'] ?? 'current';
      final outDir = Directory('build/replay_out/$label')
        ..createSync(recursive: true);
      final clips = replayDir.listSync().whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      final rows = <ClipMetrics>[];
      for (final clip in clips) {
        rows.add(_replay(clip, outDir));
      }
      final total = ClipMetrics.combine(rows);
      final table = StringBuffer()
        ..writeln(ClipMetrics.header)
        ..writeAll([
          for (final r in [...rows, total]) r.row,
        ], '\n');
      File('${outDir.path}/metrics.txt').writeAsStringSync('$table\n');
      // ignore: avoid_print
      print(table);
    },
    skip: replayDir.existsSync()
        ? false
        : 'No replay frames (see doc comment).',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

ClipMetrics _replay(Directory clip, Directory outDir) {
  final name = clip.uri.pathSegments.where((s) => s.isNotEmpty).last;
  final frames =
      clip
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.pgm'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final analyzer = FrameAnalyzer();
  final captureDir = Directory('${outDir.path}/$name');
  if (captureDir.existsSync()) captureDir.deleteSync(recursive: true);
  captureDir.createSync();
  final log = <Map<String, Object>>[];
  final metrics = ClipMetrics(name);
  final lastSeen = <int, int>{};
  final previousQuad = <int, Quad>{};

  for (final (index, file) in frames.indexed) {
    final frame = _readPgm(file);
    final analysis = analyzer.analyze(frame);
    metrics.frames++;
    metrics.totalMs += analysis.elapsedMs;
    if (analysis.covers.isNotEmpty) metrics.framesWithCover++;
    for (final cover in analysis.covers) {
      metrics.ids.add(cover.id);
      final last = lastSeen[cover.id];
      if (last != null && last < index - 1) metrics.reappearances++;
      lastSeen[cover.id] = index;
      final previous = cover.detected ? previousQuad[cover.id] : null;
      if (previous != null) {
        final s = cover.quad.sides;
        final size = (s[0] + s[1] + s[2] + s[3]) / 4;
        metrics.jitter.add(previous.meanCornerDistance(cover.quad) / size);
      }
      if (cover.detected) {
        previousQuad[cover.id] = cover.quad;
      } else {
        previousQuad.remove(cover.id);
      }
      // A cover cut off by the frame edge is not square on screen.
      if (!cover.touchesBorder && !_squareEnough(cover.quad, frame)) {
        metrics.nonSquare++;
      }
      metrics.shown++;
    }
    metrics.captures += analysis.captures.length;
    for (final capture in analysis.captures) {
      File(
        '${outDir.path}/$name/${index.toString().padLeft(5, '0')}'
        '_${capture.trackId}.jpg',
      ).writeAsBytesSync(capture.jpeg);
    }
    log.add({
      'frame': index,
      'covers': [
        for (final c in analysis.covers)
          {
            'id': c.id,
            'border': c.touchesBorder,
            'coasting': !c.detected,
            'captured': c.captured,
            'quad': [
              for (final p in c.quad.corners) [p.x, p.y],
            ],
          },
      ],
      'captures': [for (final c in analysis.captures) c.trackId],
    });
  }
  // A track shown for one or two frames only is flicker or a false outline.
  final lifetimes = <int, int>{};
  for (final entry in log) {
    for (final c in entry['covers']! as List) {
      final id = (c as Map)['id'] as int;
      lifetimes[id] = (lifetimes[id] ?? 0) + 1;
    }
  }
  metrics.tracks = metrics.ids.length;
  metrics.shortTracks = lifetimes.values.where((n) => n <= 2).length;
  File('${outDir.path}/$name.json').writeAsStringSync(jsonEncode(log));
  return metrics;
}

/// Width/height of the cover in pixels, which should be about 1 for a
/// sleeve seen roughly head-on.
bool _squareEnough(Quad quad, CameraFrame frame) {
  final q = quad.scale(frame.width.toDouble(), frame.height.toDouble());
  final aspect = q.aspectRatio;
  return aspect >= 0.75 && aspect <= 1.33;
}

CameraFrame _readPgm(File file) {
  final bytes = file.readAsBytesSync();
  // Header: "P5\n<w> <h>\n255\n".
  var offset = 0;
  final fields = <String>[];
  while (fields.length < 4) {
    final start = offset;
    while (bytes[offset] != 0x20 && bytes[offset] != 0x0a) {
      offset++;
    }
    fields.add(String.fromCharCodes(bytes.sublist(start, offset)));
    offset++;
  }
  final width = int.parse(fields[1]);
  final height = int.parse(fields[2]);
  // Chroma is subsampled 2 x 2, rounding up for odd sizes.
  final chromaWidth = (width + 1) ~/ 2;
  final chromaHeight = (height + 1) ~/ 2;
  final chroma = Uint8List(chromaWidth * chromaHeight)
    ..fillRange(0, chromaWidth * chromaHeight, 128);
  return CameraFrame(
    width: width,
    height: height,
    y: Uint8List.sublistView(bytes, offset, offset + width * height),
    yRowStride: width,
    u: chroma,
    v: chroma,
    uvRowStride: chromaWidth,
    uvPixelStride: 1,
  );
}

class ClipMetrics {
  ClipMetrics(this.name);

  final String name;
  int frames = 0;
  int framesWithCover = 0;
  int shown = 0;
  int nonSquare = 0;
  int reappearances = 0;
  int shortTracks = 0;
  int captures = 0;
  int totalMs = 0;
  int tracks = 0;
  final Set<int> ids = {};
  final List<double> jitter = [];

  static ClipMetrics combine(List<ClipMetrics> rows) {
    final all = ClipMetrics('ALL');
    for (final r in rows) {
      all
        ..frames += r.frames
        ..framesWithCover += r.framesWithCover
        ..shown += r.shown
        ..nonSquare += r.nonSquare
        ..reappearances += r.reappearances
        ..shortTracks += r.shortTracks
        ..captures += r.captures
        ..totalMs += r.totalMs
        ..tracks += r.tracks
        ..jitter.addAll(r.jitter);
    }
    return all;
  }

  static const header =
      'clip               frames  cover%  tracks  short  reappear  nonsq%  jitter  captures  ms/frame';

  String get row {
    final sorted = [...jitter]..sort();
    final median = sorted.isEmpty ? 0.0 : sorted[sorted.length ~/ 2];
    String pct(int a, int b) =>
        b == 0 ? '   -' : (100 * a / b).toStringAsFixed(0).padLeft(4);
    return '${name.padRight(18)} ${frames.toString().padLeft(6)}  '
        '${pct(framesWithCover, frames)}%  ${tracks.toString().padLeft(6)}  '
        '${shortTracks.toString().padLeft(5)}  ${reappearances.toString().padLeft(8)}  '
        '${pct(nonSquare, shown)}%  ${median.toStringAsFixed(3).padLeft(6)}  '
        '${captures.toString().padLeft(8)}  '
        '${(frames == 0 ? 0 : totalMs / frames).toStringAsFixed(1).padLeft(8)}';
  }
}
