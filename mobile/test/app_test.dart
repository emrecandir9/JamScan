import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/app.dart';

void main() {
  testWidgets('application starts and displays the welcome screen', (
    tester,
  ) async {
    await tester.pumpWidget(const JamScanApp());

    expect(find.text('JamSCAN'), findsOneWidget);
    expect(find.text('Welcome to JamSCAN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
