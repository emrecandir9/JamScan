// Opt-in Android smoke test: flutter run -t tool/preview_smoke.dart -d <device>
// Uses public iTunes previews; does not test S2-07 recognition/catalogue wiring.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:jamscan/app.dart';
import 'package:jamscan/app_scope.dart';
import 'package:jamscan/models/album.dart';
import 'package:jamscan/services/live_scanner.dart';
import 'package:jamscan/state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final deps = AppDependencies(
    liveScanner: UnavailableLiveScanner(),
    settings: SettingsController(autoplayTopTrack: false),
  );
  runApp(JamScanApp(dependencies: deps));
  try {
    final response = await http
        .get(
          Uri.https('itunes.apple.com', '/search', {
            'term': 'Daft Punk',
            'country': 'FR',
            'media': 'music',
            'entity': 'song',
            'limit': '10',
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('iTunes HTTP ${response.statusCode}');
    }
    final results =
        (jsonDecode(response.body) as Map<String, dynamic>)['results'] as List;
    final songs = results
        .cast<Map<String, dynamic>>()
        .where(
          (song) =>
              song['artistName'] == 'Daft Punk' && song['previewUrl'] is String,
        )
        .take(2)
        .toList();
    if (songs.isEmpty) throw StateError('No iTunes preview available');
    final tracks = [
      for (final (index, song) in songs.indexed)
        Track(
          position: '${index + 1}',
          title: song['trackName'] as String,
          duration: Duration(milliseconds: song['trackTimeMillis'] as int),
          previewUrl: song['previewUrl'] as String,
        ),
    ];
    final album = Album(
      id: 'smoke-itunes',
      title: songs.first['collectionName'] as String,
      artist: 'Daft Punk',
      year: 2013,
      format: MediaFormat.vinyl,
      formatDescription: 'Playback smoke test',
      pressingFormat: '',
      label: '',
      catalogNumber: '',
      country: '',
      genres: const [],
      tracks: tracks,
    );
    deps.shell.showResult(album);
    await deps.player.play(album, tracks.first);
    await Future<void>.delayed(const Duration(seconds: 3));
    check(
      deps.player.isPlaying && deps.player.position > Duration.zero,
      'real decoder advances',
    );
    await deps.player.pause();
    final paused = deps.player.position;
    await Future<void>.delayed(const Duration(seconds: 1));
    check(
      !deps.player.isPlaying &&
          (deps.player.position - paused).abs() <
              const Duration(milliseconds: 300),
      'pause holds position',
    );
    await deps.player.play(album, tracks.first);
    await Future<void>.delayed(const Duration(seconds: 2));
    check(deps.player.position > paused, 'resume advances');
    if (tracks.length > 1) {
      await deps.player.play(album, tracks.last);
      check(deps.player.track == tracks.last, 'track switch');
    }
    await Future<void>.delayed(const Duration(seconds: 32));
    check(
      !deps.player.isPlaying &&
          deps.player.progress == 1 &&
          deps.player.clipLength <= const Duration(seconds: 30),
      'preview completes within 30 seconds',
    );
    await deps.player.play(album, deps.player.track!);
    await Future<void>.delayed(const Duration(seconds: 2));
    check(
      deps.player.isPlaying &&
          deps.player.position < const Duration(seconds: 5),
      'completed preview replays',
    );
    deps.player.stop();
    check(deps.player.track == null, 'stop clears playback');
    debugPrint('S2-06 SMOKE PASSED');
  } catch (error) {
    debugPrint('S2-06 SMOKE FAILED: $error');
  }
}

void check(bool condition, String description) {
  if (!condition) throw StateError(description);
  debugPrint('S2-06 PASS: $description');
}
