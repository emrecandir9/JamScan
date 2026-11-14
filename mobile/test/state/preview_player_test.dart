import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:jamscan/state/preview_player.dart';

import '../support/fake_preview_audio.dart';

void main() {
  late List<FakePreviewAudio> engines;
  late PreviewPlayer player;
  final a = previewTrack('A1');
  final b = previewTrack('A2');
  final album = previewAlbum([a, b]);

  setUp(() {
    engines = [];
    player = PreviewPlayer(
      audioFactory: () {
        final engine = FakePreviewAudio();
        engines.add(engine);
        return engine;
      },
    );
  });
  tearDown(() => player.dispose());

  test(
    'loads HTTPS audio clipped at 30s; pauses and resumes without reload',
    () async {
      await player.play(album, a);
      final engine = engines.single;
      expect(engine.url, a.previewUrl);
      expect(engine.limit, const Duration(seconds: 30));
      expect(player.isPlaying, isTrue);
      engine.positionEvents.add(const Duration(seconds: 12));
      expect(player.progress, .4);
      await player.toggle(album, a);
      expect(player.isPlaying, isFalse);
      expect(player.position, const Duration(seconds: 12));
      await player.toggle(album, a);
      expect(engine.playCalls, 2);
      expect(engines, hasLength(1));
    },
  );

  test(
    'uses actual short duration and replays from zero on completion',
    () async {
      await player.play(album, a);
      final engine = engines.single;
      engine.durationEvents.add(const Duration(seconds: 18));
      engine.stateEvents.add(PlayerState(true, ProcessingState.completed));
      expect(player.isPlaying, isFalse);
      expect(player.progress, 1);
      expect(player.clipLength, const Duration(seconds: 18));
      await player.play(album, a);
      expect(engine.sought, Duration.zero);
      expect(player.position, Duration.zero);
      expect(player.isPlaying, isTrue);
    },
  );

  test('never displays more than 30 seconds and tracks buffering', () async {
    await player.play(album, a);
    final engine = engines.single;
    engine.durationEvents.add(const Duration(seconds: 90));
    engine.positionEvents.add(const Duration(seconds: 50));
    expect(player.clipLength, const Duration(seconds: 30));
    expect(player.progress, 1);
    engine.stateEvents.add(PlayerState(true, ProcessingState.buffering));
    expect(player.isLoading, isTrue);
  });

  test('switching disposes previous audio and resets position', () async {
    await player.play(album, a);
    engines.first.positionEvents.add(const Duration(seconds: 8));
    await player.play(album, b);
    expect(engines.first.disposed, isTrue);
    expect(player.track, b);
    expect(player.position, Duration.zero);
    expect(engines.last.playCalls, 1);
  });

  test('stop clears selection and releases audio', () async {
    await player.play(album, a);
    player.stop();
    expect(engines.single.disposed, isTrue);
    expect(player.track, isNull);
    expect(player.isPlaying, isFalse);
    expect(player.position, Duration.zero);
  });

  test('missing or invalid URLs never create an audio player', () async {
    for (final url in [
      null,
      '',
      'not a url',
      'http://example.test/a',
      'file:///tmp/a',
    ]) {
      final track = previewTrack('missing', url: url);
      await player.play(previewAlbum([track]), track);
      expect(player.error, contains('No preview'));
      expect(player.isPlaying, isFalse);
    }
    expect(engines, isEmpty);
  });

  test(
    'runtime failure releases audio and retry creates a fresh source',
    () async {
      await player.play(album, a);
      engines.single.errorEvents.add(Exception('network lost'));
      expect(player.error, contains('retry'));
      expect(player.isPlaying, isFalse);
      expect(engines.single.disposed, isTrue);
      await player.play(album, a);
      expect(player.error, isNull);
      expect(player.isPlaying, isTrue);
      expect(engines, hasLength(2));
    },
  );

  test('load failure is caught', () async {
    player.dispose();
    final engine = FakePreviewAudio()..loadError = Exception('404');
    player = PreviewPlayer(audioFactory: () => engine);
    await player.play(album, a);
    expect(player.error, contains('retry'));
    expect(engine.disposed, isTrue);
  });

  test('pause during pending load prevents autoplay', () async {
    player.dispose();
    final pending = Completer<void>();
    final engine = FakePreviewAudio()..pendingLoad = pending;
    player = PreviewPlayer(audioFactory: () => engine);
    final request = player.play(album, a);
    await Future<void>.delayed(Duration.zero);
    await player.pause();
    pending.complete();
    await request;
    expect(engine.playCalls, 0);
    await player.play(album, a);
    expect(engine.playCalls, 1);
  });

  test(
    'late completion of replaced load cannot start or overwrite new track',
    () async {
      player.dispose();
      final pending = Completer<void>();
      final first = FakePreviewAudio()..pendingLoad = pending;
      final second = FakePreviewAudio();
      var calls = 0;
      player = PreviewPlayer(audioFactory: () => calls++ == 0 ? first : second);
      final oldRequest = player.play(album, a);
      await Future<void>.delayed(Duration.zero);
      await player.play(album, b);
      pending.complete();
      await oldRequest;
      expect(first.playCalls, 0);
      expect(first.disposed, isTrue);
      expect(second.playCalls, 1);
      expect(player.track, b);
      expect(player.error, isNull);
    },
  );

  test('timeout disposes the load and late completion cannot play', () async {
    player.dispose();
    final pending = Completer<void>();
    final engine = FakePreviewAudio()..pendingLoad = pending;
    player = PreviewPlayer(
      audioFactory: () => engine,
      loadTimeout: const Duration(milliseconds: 5),
    );
    await player.play(album, a);
    expect(player.error, contains('retry'));
    expect(engine.disposed, isTrue);
    pending.complete();
    await Future<void>.delayed(Duration.zero);
    expect(engine.playCalls, 0);
  });

  test('dispose during loading ignores late completion', () async {
    player.dispose();
    final pending = Completer<void>();
    final engine = FakePreviewAudio()..pendingLoad = pending;
    player = PreviewPlayer(audioFactory: () => engine);
    final request = player.play(album, a);
    await Future<void>.delayed(Duration.zero);
    player.dispose();
    pending.complete();
    await request;
    expect(engine.disposed, isTrue);
    expect(engine.playCalls, 0);
    // Replace for tearDown, avoiding a second ChangeNotifier disposal.
    player = PreviewPlayer();
  });

  test('ranks playable tracks, then uses stable release order without inventing ranks', () {
    final tracks = [
      previewTrack('1'),
      previewTrack('2', rank: 2),
      previewTrack('3', rank: 1),
      previewTrack('4', rank: 1),
      previewTrack('5', url: null),
      previewTrack('6'),
      previewTrack('7'),
    ];
    expect(previewAlbum(tracks).topTracks.map((t) => t.position), [
      '3',
      '4',
      '2',
      '1',
      '6',
    ]);
    expect(previewAlbum([a, b]).topTracks, [a, b]);
  });
}
