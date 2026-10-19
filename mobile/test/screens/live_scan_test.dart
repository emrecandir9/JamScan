import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/services/live_scanner.dart';
import 'package:jamscan/state/shell_controller.dart';

import '../support/fake_live_scanner.dart';
import '../support/test_app.dart';

void main() {
  testWidgets('the scan page starts the live camera', (tester) async {
    final live = FakeLiveScanner();

    await pumpApp(tester, dependencies: testDependencies(liveScanner: live));

    expect(live.startCalls, 1);
    expect(find.text('Point the camera at album covers'), findsOneWidget);
    expect(find.text('Tap the shutter to photograph a cover'), findsNothing);
  });

  testWidgets('the shutter photographs with the live camera', (tester) async {
    final live = FakeLiveScanner();
    final camera = FakeCamera();
    await pumpApp(
      tester,
      dependencies: testDependencies(liveScanner: live, camera: camera),
    );

    await tapKey(tester, 'capture.shutter');

    expect(live.pictureCalls, 1);
    expect(camera.captureCalls, 0);
    expect(inResultCard('Kind of Blue'), findsOneWidget);
  });

  testWidgets('falls back to the system camera without a live camera', (
    tester,
  ) async {
    final live = FakeLiveScanner(startsAs: LiveScannerState.unavailable);
    final camera = FakeCamera()..result = capturedPhoto();
    await pumpApp(
      tester,
      dependencies: testDependencies(liveScanner: live, camera: camera),
    );

    await tapKey(tester, 'capture.shutter');

    expect(live.pictureCalls, 0);
    expect(camera.captureCalls, 1);
  });

  testWidgets('a refused permission shows the camera-off page', (tester) async {
    final live = FakeLiveScanner(
      startsAs: LiveScannerState.permissionPermanentlyDenied,
    );

    await pumpApp(tester, dependencies: testDependencies(liveScanner: live));

    expect(find.text('Camera access is off'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
  });

  testWidgets('allowing access after a refusal asks again', (tester) async {
    final live = FakeLiveScanner(startsAs: LiveScannerState.permissionDenied);
    await pumpApp(tester, dependencies: testDependencies(liveScanner: live));
    expect(find.text('Camera access is off'), findsOneWidget);

    live.startsAs = LiveScannerState.running;
    await tester.tap(find.text('Allow camera access'));
    await tester.pumpAndSettle();

    expect(live.accessRequests, 1);
    expect(find.text('Point the camera at album covers'), findsOneWidget);
  });

  testWidgets('leaving the scan tab stops the camera', (tester) async {
    final live = FakeLiveScanner();
    final deps = await pumpApp(
      tester,
      dependencies: testDependencies(liveScanner: live),
    );

    deps.shell.tab = AppTab.library;
    await tester.pumpAndSettle();
    expect(live.stopCalls, greaterThanOrEqualTo(1));
    expect(live.state, LiveScannerState.idle);

    deps.shell.tab = AppTab.scan;
    await tester.pumpAndSettle();
    expect(live.state, LiveScannerState.running);
  });

  testWidgets('analysis pauses while another page is on top', (tester) async {
    final live = FakeLiveScanner();
    await pumpApp(tester, dependencies: testDependencies(liveScanner: live));
    expect(live.analysisPaused, isFalse);

    await tapKey(tester, 'taskbar.search');
    expect(live.analysisPaused, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(live.analysisPaused, isFalse);
    expect(find.byType(BackButton), findsNothing);
  });
}
