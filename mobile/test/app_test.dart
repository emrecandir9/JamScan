import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/app.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('application starts on the Scan tab', (tester) async {
    await pumpApp(tester);

    expect(find.text('Fit the album cover inside the frame'), findsOneWidget);
    expect(find.byKey(const Key('taskbar.history')), findsOneWidget);
    expect(find.byKey(const Key('taskbar.scan')), findsOneWidget);
    expect(find.byKey(const Key('taskbar.search')), findsOneWidget);
    expect(find.byKey(const Key('capture.shutter')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('application builds with its default dependencies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const JamScanApp());
    await tester.pumpAndSettle();

    expect(find.text('Fit the album cover inside the frame'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
