import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:jamscan/models/album.dart';
import 'package:jamscan/services/preview_audio.dart';
import 'package:jamscan/services/catalog_service.dart';

class FakePreviewAudio implements PreviewAudio {
  final stateEvents = StreamController<PlayerState>.broadcast(sync: true);
  final positionEvents = StreamController<Duration>.broadcast(sync: true);
  final durationEvents = StreamController<Duration?>.broadcast(sync: true);
  final errorEvents = StreamController<Object>.broadcast(sync: true);
  Completer<void>? pendingLoad;
  Object? loadError;
  bool disposed = false;
  int playCalls = 0;
  int pauseCalls = 0;
  String? url;
  Duration? limit;
  Duration? sought;

  @override
  Stream<PlayerState> get states => stateEvents.stream;
  @override
  Stream<Duration> get positions => positionEvents.stream;
  @override
  Stream<Duration?> get durations => durationEvents.stream;
  @override
  Stream<Object> get errors => errorEvents.stream;
  @override
  Future<void> load(String url, Duration limit) async {
    this.url = url;
    this.limit = limit;
    if (pendingLoad != null) await pendingLoad!.future;
    if (loadError != null) throw loadError!;
    if (!disposed) stateEvents.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> play() async {
    playCalls++;
    stateEvents.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    stateEvents.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> seek(Duration position) async {
    sought = position;
    positionEvents.add(position);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await Future.wait([
      stateEvents.close(),
      positionEvents.close(),
      durationEvents.close(),
      errorEvents.close(),
    ]);
  }
}

Track previewTrack(
  String position, {
  int? rank,
  String? url = 'https://example.test/preview.m4a',
}) => Track(
  position: position,
  title: 'Track $position',
  duration: const Duration(minutes: 4),
  popularityRank: rank,
  previewUrl: url,
);

Album previewAlbum(List<Track> tracks, {String id = '123'}) => Album(
  id: id,
  title: 'Test album',
  artist: 'Test artist',
  year: 2026,
  format: MediaFormat.vinyl,
  formatDescription: 'Vinyl LP',
  pressingFormat: 'Vinyl',
  label: 'Label',
  catalogNumber: '',
  country: '',
  genres: const [],
  tracks: tracks,
);

class PreviewCatalog extends MockCatalogService {
  @override
  Future<List<Album>> search(String query) async => [
    previewAlbum([
      previewTrack('A1'),
      previewTrack('A2'),
      previewTrack('A3', url: null),
    ]),
  ];
}
