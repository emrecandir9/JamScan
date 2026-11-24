import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/services/live_scanner.dart';

class _Plane implements Plane {
  _Plane(this.bytes, this.bytesPerRow, [this.bytesPerPixel]);

  @override
  final Uint8List bytes;
  @override
  final int bytesPerRow;
  @override
  final int? bytesPerPixel;
  @override
  int? get height => null;
  @override
  int? get width => null;
}

class _Image implements CameraImage {
  _Image(this.width, this.height, this.planes);

  @override
  final int width;
  @override
  final int height;
  @override
  final List<Plane> planes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // A 4x2 frame whose left 2x2 block has chroma (Cb 90, Cr 200) and right
  // block (Cb 170, Cr 60).
  final luma = Uint8List.fromList(List.filled(8, 120));

  test('Android three-plane frames keep the sensor rotation', () {
    final image = _Image(4, 2, [
      _Plane(luma, 4),
      _Plane(Uint8List.fromList([90, 170]), 2, 1),
      _Plane(Uint8List.fromList([200, 60]), 2, 1),
    ]);

    final frame = copyCameraFrame(image, 90);

    expect(frame.rotationDegrees, 90);
    expect(frame.rgbAt(0, 0), isNot(frame.rgbAt(3, 1)));
  });

  test('iOS NV12 frames read the same colours as three-plane frames', () {
    final planar = copyCameraFrame(
      _Image(4, 2, [
        _Plane(luma, 4),
        _Plane(Uint8List.fromList([90, 170]), 2, 1),
        _Plane(Uint8List.fromList([200, 60]), 2, 1),
      ]),
      90,
    );
    final nv12 = copyCameraFrame(
      _Image(4, 2, [
        _Plane(luma, 4),
        _Plane(Uint8List.fromList([90, 200, 170, 60]), 4, 2),
      ]),
      90,
    );

    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 4; x++) {
        expect(nv12.rgbAt(x, y), planar.rgbAt(x, y), reason: '($x, $y)');
      }
    }
  });

  test('portrait frames from iOS are already upright', () {
    final image = _Image(2, 4, [
      _Plane(Uint8List(8), 2),
      _Plane(Uint8List(4), 2, 2),
    ]);

    expect(copyCameraFrame(image, 90).rotationDegrees, 0);
  });
}
