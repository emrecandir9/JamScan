import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/screens/camera_capture_screen.dart';
import 'package:jamscan/services/camera_capture_service.dart';

class FakeCameraService extends CameraCaptureService {
  CameraCaptureResult result = const CameraCaptureResult(
    CameraCaptureStatus.cancelled,
  );

  Completer<CameraCaptureResult>? pending;
  int captureCalls = 0;
  int settingsCalls = 0;

  @override
  Future<CameraCaptureResult> capture() async {
    captureCalls++;
    return pending == null ? result : await pending!.future;
  }

  @override
  Future<CameraCaptureResult?> recoverLostCapture() async => null;

  @override
  Future<bool> openSettings() async {
    settingsCalls++;
    return true;
  }
}

Future<void> showCamera(WidgetTester tester, FakeCameraService service) async {
  await tester.pumpWidget(
    MaterialApp(home: CameraCaptureScreen(service: service)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cancelling allows another capture attempt', (tester) async {
    final service = FakeCameraService();
    await showCamera(tester, service);

    await tester.tap(find.text('Photograph cover'));
    await tester.pumpAndSettle();

    expect(find.text('Capture cancelled.'), findsOneWidget);

    await tester.tap(find.text('Photograph cover'));
    await tester.pumpAndSettle();

    expect(service.captureCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('denied permission shows an explanation', (tester) async {
    final service = FakeCameraService()
      ..result = const CameraCaptureResult(
        CameraCaptureStatus.permissionDenied,
      );
    await showCamera(tester, service);

    await tester.tap(find.text('Photograph cover'));
    await tester.pumpAndSettle();

    expect(
      find.text('Camera permission is needed to photograph the cover.'),
      findsOneWidget,
    );
    expect(find.text('Open settings'), findsNothing);
  });

  testWidgets('permanently denied permission allows opening settings', (
    tester,
  ) async {
    final service = FakeCameraService()
      ..result = const CameraCaptureResult(
        CameraCaptureStatus.permissionPermanentlyDenied,
      );
    await showCamera(tester, service);

    await tester.tap(find.text('Photograph cover'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    expect(service.settingsCalls, 1);
    expect(
      find.text(
        'After returning from settings, tap the button to take a photo.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an error shows a message and allows retrying', (tester) async {
    final service = FakeCameraService()
      ..result = const CameraCaptureResult(CameraCaptureStatus.failed);
    await showCamera(tester, service);

    await tester.tap(find.text('Photograph cover'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not capture the photo. Please try again.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Photograph cover'));
    await tester.pumpAndSettle();

    expect(service.captureCalls, 2);
  });

  testWidgets('does not start another capture while one is pending', (
    tester,
  ) async {
    final pending = Completer<CameraCaptureResult>();
    final service = FakeCameraService()..pending = pending;
    await showCamera(tester, service);

    await tester.tap(find.text('Photograph cover'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Photograph cover'));
    await tester.pump();

    expect(service.captureCalls, 1);

    pending.complete(const CameraCaptureResult(CameraCaptureStatus.cancelled));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Capture cancelled.'), findsOneWidget);
  });
}
