import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/mock/mock_catalog.dart';
import 'package:jamscan/models/library.dart';

import '../support/test_app.dart';

void main() {
  Future<void> openMyVinyl(WidgetTester tester) async {
    await tapKey(tester, 'capture.library');
    await tester.tap(find.text('My Vinyl'));
    await tester.pumpAndSettle();
  }

  testWidgets('library shows collections and wishlists', (tester) async {
    await pumpApp(tester, dependencies: testDependencies(signedIn: true));
    await tapKey(tester, 'capture.library');

    expect(find.text('My Vinyl'), findsOneWidget);
    expect(find.text('Jazz Shelf'), findsOneWidget);
    expect(find.text('4 owned · 2 ghosts'), findsOneWidget);

    await tester.tap(find.text('Wishlists'));
    await tester.pumpAndSettle();

    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('2 albums'), findsOneWidget);
  });

  testWidgets('a list shows its albums and ghosts', (tester) async {
    await pumpApp(tester, dependencies: testDependencies(signedIn: true));
    await openMyVinyl(tester);

    expect(find.text('Kind of Blue'), findsOneWidget);
    expect(find.text('A Love Supreme'), findsOneWidget);
    expect(find.text('Ghost'), findsNWidgets(2));
    expect(find.byKey(const Key('taskbar.library')), findsOneWidget);
  });

  testWidgets('a search without matches offers to clear filters', (
    tester,
  ) async {
    await pumpApp(tester, dependencies: testDependencies(signedIn: true));
    await openMyVinyl(tester);

    await tester.enterText(find.byKey(const Key('list.search')), 'zeppelin x');
    await tester.pumpAndSettle();
    expect(find.text('No albums match'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Kind of Blue'), findsOneWidget);
  });

  testWidgets('filters hide ghosts', (tester) async {
    await pumpApp(tester, dependencies: testDependencies(signedIn: true));
    await openMyVinyl(tester);

    await tester.tap(find.text('Date added'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Ghosts'));
    await tester.pumpAndSettle();
    expect(find.text('Show 4 albums'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('filter.apply')));
    await tester.pumpAndSettle();
    await tapKey(tester, 'filter.apply');

    expect(find.text('A Love Supreme'), findsNothing);
    expect(find.text('Kind of Blue'), findsOneWidget);
  });

  testWidgets('a new list cannot reuse an existing name', (tester) async {
    final deps = await pumpApp(
      tester,
      dependencies: testDependencies(signedIn: true),
    );
    await tapKey(tester, 'capture.library');

    await tester.tap(find.byTooltip('New list'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('listName.field')),
      'jazz shelf',
    );
    await tester.pump();
    expect(find.text('A list with this name already exists'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('listName.field')),
      'Shop finds',
    );
    await tester.pump();
    await tapKey(tester, 'listName.confirm');

    final names = deps.library
        .listsOf(ListKind.collection)
        .map((list) => list.name);
    expect(names, contains('Shop finds'));
  });

  testWidgets('bulk select removes albums', (tester) async {
    final deps = await pumpApp(
      tester,
      dependencies: testDependencies(signedIn: true),
    );
    await openMyVinyl(tester);

    await tester.longPress(find.text('Rumours'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.text('Blue Train'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Remove 2 albums?'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Rumours'), findsNothing);
    expect(find.text('Removed 2 albums'), findsOneWidget);
    final myVinyl = deps.library.listsOf(ListKind.collection).first;
    expect(myVinyl.containsAlbum(MockCatalog.rumours.id), isFalse);
  });

  testWidgets('a ghost can be marked as owned', (tester) async {
    final deps = await pumpApp(
      tester,
      dependencies: testDependencies(signedIn: true),
    );
    await openMyVinyl(tester);

    await tester.tap(find.byTooltip('Options for A Love Supreme'));
    await tester.pumpAndSettle();
    expect(find.text('Ghost in My Vinyl'), findsOneWidget);

    await tester.tap(find.text('I bought it – mark as owned'));
    await tester.pumpAndSettle();

    expect(find.text('Marked as owned in My Vinyl'), findsOneWidget);
    final entry = deps.library
        .listsOf(ListKind.collection)
        .first
        .entries
        .firstWhere((entry) => entry.album.id == MockCatalog.loveSupreme.id);
    expect(entry.isGhost, isFalse);
  });
}
