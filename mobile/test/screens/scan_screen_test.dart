import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jamscan/services/camera_capture_service.dart';
import 'package:jamscan/services/gallery_import_service.dart';

import '../support/test_app.dart';

/// The S1-03 camera behaviours, now on the Scan tab.
void main() {
  Future<FakeCamera> showScan(
    WidgetTester tester, {
    CameraCaptureResult? result,
  }) async {
    final camera = FakeCamera();
    if (result != null) {
      camera.result = result;
    }
    await pumpApp(tester, dependencies: testDependencies(camera: camera));
    return camera;
  }

  testWidgets('cancelling allows another capture attempt', (tester) async {
    final camera = await showScan(tester);

    await tapKey(tester, 'capture.shutter');
    expect(find.text('Capture cancelled.'), findsOneWidget);

    await waitForSnackBarToClose(tester);
    await tapKey(tester, 'capture.shutter');

    expect(camera.captureCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('denied permission shows the camera access page', (
    tester,
  ) async {
    await showScan(
      tester,
      result: const CameraCaptureResult(CameraCaptureStatus.permissionDenied),
    );

    await tapKey(tester, 'capture.shutter');

    expect(find.text('Camera access is off'), findsOneWidget);
    expect(find.text('Allow camera access'), findsOneWidget);
    expect(find.text('Search manually'), findsOneWidget);
    expect(find.text('Open settings'), findsNothing);
  });

  testWidgets('permanently denied permission allows opening settings', (
    tester,
  ) async {
    final camera = await showScan(
      tester,
      result: const CameraCaptureResult(
        CameraCaptureStatus.permissionPermanentlyDenied,
      ),
    );

    await tapKey(tester, 'capture.shutter');
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    expect(camera.settingsCalls, 1);
    expect(
      find.text(
        'After returning from settings, tap the shutter to take a photo.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('access comes back once a capture succeeds', (tester) async {
    final camera = await showScan(
      tester,
      result: const CameraCaptureResult(CameraCaptureStatus.permissionDenied),
    );
    await tapKey(tester, 'capture.shutter');
    expect(find.text('Camera access is off'), findsOneWidget);

    camera.result = capturedPhoto();
    await tester.tap(find.text('Allow camera access'));
    await tester.pumpAndSettle();

    expect(find.text('Camera access is off'), findsNothing);
    expect(find.byKey(const Key('scan.resultCard')), findsOneWidget);
  });

  testWidgets('an error shows a message and allows retrying', (tester) async {
    final camera = await showScan(
      tester,
      result: const CameraCaptureResult(CameraCaptureStatus.failed),
    );

    await tapKey(tester, 'capture.shutter');
    expect(
      find.text('Could not capture the photo. Please try again.'),
      findsOneWidget,
    );

    await waitForSnackBarToClose(tester);
    await tapKey(tester, 'capture.shutter');

    expect(camera.captureCalls, 2);
  });

  testWidgets('does not start another capture while one is pending', (
    tester,
  ) async {
    final camera = await showScan(tester);
    final pending = Completer<CameraCaptureResult>();
    camera.pending = pending;

    await tester.tap(find.byKey(const Key('capture.shutter')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('capture.shutter')));
    await tester.pump();

    expect(camera.captureCalls, 1);

    pending.complete(
      const CameraCaptureResult(CameraCaptureStatus.cancelled),
    );
    await tester.pumpAndSettle();

    expect(find.text('Capture cancelled.'), findsOneWidget);
  });

  testWidgets('an imported photo is identified', (tester) async {
    final gallery = FakeGallery()
      ..result = GalleryImportResult(
        GalleryImportStatus.selected,
        image: XFile(testPhotoPath),
      );
    await pumpApp(tester, dependencies: testDependencies(gallery: gallery));

    await tapKey(tester, 'capture.gallery');

    expect(find.byKey(const Key('scan.resultCard')), findsOneWidget);
  });
}
