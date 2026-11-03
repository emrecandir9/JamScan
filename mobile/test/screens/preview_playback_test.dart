import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/state/preview_player.dart';

import '../support/fake_preview_audio.dart';
import '../support/test_app.dart';

void main() {
  testWidgets(
    'details play/pause, loading, retry, stop and unavailable controls',
    (tester) async {
      final engines = <FakePreviewAudio>[];
      final pending = Completer<void>();
      final player = PreviewPlayer(
        audioFactory: () {
          final audio = FakePreviewAudio();
          if (engines.isEmpty) audio.pendingLoad = pending;
          engines.add(audio);
          return audio;
        },
      );
      await pumpApp(
        tester,
        dependencies: testDependencies(
          player: player,
          catalog: PreviewCatalog(),
        ),
      );
      await showResultViaSearch(tester, query: 'test', title: 'Test album');
      await tester.tap(find.text('Learn more'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Preview unavailable'), findsOneWidget);
      final unavailable = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconButton && widget.tooltip == 'Preview unavailable',
        ),
      );
      expect(unavailable.onPressed, isNull);
      await tester.tap(find.byTooltip('Play preview').first);
      await tester.pump();
      await tester.pump();
      expect(find.text('Loading preview…'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause preview').first);
      await tester.pump();
      pending.complete();
      await tester.pumpAndSettle();
      expect(engines.single.playCalls, 0);
      await tester.tap(find.byTooltip('Play preview').first);
      await tester.pumpAndSettle();
      expect(player.isPlaying, isTrue);
      engines.single.errorEvents.add(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Tracklist'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(engines, hasLength(2));
      expect(player.isPlaying, isTrue);
      await tester.tap(find.byTooltip('Stop preview'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('miniPlayer')), findsNothing);
      expect(engines.last.disposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('backgrounding pauses audio without resuming on return', (
    tester,
  ) async {
    final audio = FakePreviewAudio();
    final player = PreviewPlayer(audioFactory: () => audio);
    await pumpApp(tester, dependencies: testDependencies(player: player));
    final track = previewTrack('A1');
    await player.play(previewAlbum([track]), track);
    expect(player.isPlaying, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(player.isPlaying, isFalse);
    expect(audio.pauseCalls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(player.isPlaying, isFalse);
  });

  testWidgets('scan previews without popularity can play and switch', (
    tester,
  ) async {
    final engines = <FakePreviewAudio>[];
    final player = PreviewPlayer(
      audioFactory: () {
        final audio = FakePreviewAudio();
        engines.add(audio);
        return audio;
      },
    );
    await pumpApp(
      tester,
      dependencies: testDependencies(player: player, catalog: PreviewCatalog()),
    );
    await showResultViaSearch(tester, query: 'test', title: 'Test album');
    expect(find.textContaining('Popular'), findsNothing);
    await tester.tap(find.byTooltip('Play preview'));
    await tester.pumpAndSettle();
    expect(player.track?.position, 'A1');
    await tapKey(tester, 'scan.allTracks');
    await tester.tap(find.byTooltip('Play Track A2'));
    await tester.pumpAndSettle();
    expect(player.track?.position, 'A2');
    expect(engines.first.disposed, isTrue);
    await tester.tap(find.text('Stop preview'));
    await tester.pumpAndSettle();
    expect(player.track, isNull);
    expect(tester.takeException(), isNull);
  });
}
