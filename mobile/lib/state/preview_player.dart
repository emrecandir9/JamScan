import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/album.dart';

/// Simulated 30-second preview player.
///
/// There is no audio package in the project yet, so this only tracks which
/// preview is "playing" and advances the position once per second. The
/// screens depend on this API only; swap the timer for a real player
/// (for example just_audio) behind it.
class PreviewPlayer extends ChangeNotifier {
  PreviewPlayer({this.clipLength = const Duration(seconds: 30)});

  final Duration clipLength;

  Album? _album;
  Track? _track;
  Duration _position = Duration.zero;
  bool _playing = false;
  Timer? _timer;

  Album? get album => _album;
  Track? get track => _track;
  Duration get position => _position;
  bool get isPlaying => _playing;

  /// Between 0 and 1.
  double get progress {
    final total = clipLength.inMilliseconds;
    return total == 0 ? 0 : _position.inMilliseconds / total;
  }

  bool isCurrent(Album album, Track track) {
    return _album?.id == album.id && _track?.position == track.position;
  }

  bool isPlayingTrack(Album album, Track track) {
    return _playing && isCurrent(album, track);
  }

  void play(Album album, Track track) {
    if (!isCurrent(album, track)) {
      _album = album;
      _track = track;
      _position = Duration.zero;
    }
    if (_position >= clipLength) {
      _position = Duration.zero;
    }
    _playing = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
  }

  void pause() {
    if (!_playing) {
      return;
    }
    _playing = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  void toggle(Album album, Track track) {
    if (isPlayingTrack(album, track)) {
      pause();
    } else {
      play(album, track);
    }
  }

  /// Stops playback and forgets the current preview.
  void stop() {
    _timer?.cancel();
    _timer = null;
    final changed = _track != null || _playing;
    _album = null;
    _track = null;
    _position = Duration.zero;
    _playing = false;
    if (changed) {
      notifyListeners();
    }
  }

  void _tick() {
    _position += const Duration(seconds: 1);
    if (_position >= clipLength) {
      _position = clipLength;
      _playing = false;
      _timer?.cancel();
      _timer = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
