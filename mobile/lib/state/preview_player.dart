import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/album.dart';
import '../services/preview_audio.dart';

/// App-wide player. Only one preview can own audio at a time.
class PreviewPlayer extends ChangeNotifier {
  PreviewPlayer({
    PreviewAudio Function()? audioFactory,
    this.loadTimeout = const Duration(seconds: 15),
  }) : _audioFactory = audioFactory ?? JustAudioPreview.new;

  static const previewLimit = Duration(seconds: 30);
  final PreviewAudio Function() _audioFactory;
  final Duration loadTimeout;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  PreviewAudio? _audio;
  Future<void> _releasing = Future.value();
  Album? _album;
  Track? _track;
  Duration _position = Duration.zero;
  Duration _duration = previewLimit;
  bool _playing = false;
  bool _loading = false;
  bool _ready = false;
  bool _wantsPlay = false;
  bool _completed = false;
  bool _disposed = false;
  int _generation = 0;
  String? _error;

  Album? get album => _album;
  Track? get track => _track;
  Duration get position => _position;
  Duration get clipLength => _duration;
  bool get isPlaying => _playing;
  bool get isLoading => _loading;
  bool get wantsPlay => _wantsPlay;
  String? get error => _error;
  double get progress => _duration.inMilliseconds == 0
      ? 0
      : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

  bool isCurrent(Album album, Track track) =>
      _album?.id == album.id &&
      _track?.position == track.position &&
      _track?.title == track.title &&
      _track?.previewUrl == track.previewUrl;

  bool isPlayingTrack(Album album, Track track) =>
      _playing && isCurrent(album, track);

  bool _active(int generation) => !_disposed && generation == _generation;

  Future<void> play(Album album, Track track) async {
    if (_disposed) return;
    if (isCurrent(album, track) && _audio != null && _error == null) {
      _wantsPlay = true;
      if (_ready) await _resume(_generation);
      return;
    }
    final generation = ++_generation;
    _release();
    _album = album;
    _track = track;
    _position = Duration.zero;
    _duration = previewLimit;
    _playing = false;
    _ready = false;
    _completed = false;
    _wantsPlay = album.previewsAvailable && track.hasPreview;
    _loading = _wantsPlay;
    _error = _wantsPlay ? null : 'No preview available for this track.';
    notifyListeners();
    if (!_wantsPlay) return;
    try {
      await _releasing;
      if (!_active(generation)) return;
      final audio = _audioFactory();
      _audio = audio;
      _subscriptions.addAll([
        audio.states.listen((state) {
          if (!_active(generation) || _error != null) return;
          _completed = state.processingState == ProcessingState.completed;
          _loading =
              state.processingState == ProcessingState.loading ||
              state.processingState == ProcessingState.buffering;
          _playing = state.playing && !_completed;
          if (_completed) {
            _wantsPlay = false;
            _position = _duration;
          }
          notifyListeners();
        }),
        audio.positions.listen((value) {
          if (!_active(generation) || _error != null) return;
          _position = value < Duration.zero
              ? Duration.zero
              : value > _duration
              ? _duration
              : value;
          notifyListeners();
        }),
        audio.durations.listen((value) {
          if (!_active(generation) || value == null || value <= Duration.zero) {
            return;
          }
          _duration = value < previewLimit ? value : previewLimit;
          notifyListeners();
        }),
        audio.errors.listen((_) => _fail(generation)),
      ]);
      await audio.load(track.previewUrl!, previewLimit).timeout(loadTimeout);
      if (!_active(generation) || _error != null) return;
      _ready = true;
      _loading = false;
      notifyListeners();
      if (_wantsPlay) await _resume(generation);
    } catch (_) {
      _fail(generation);
    }
  }

  Future<void> _resume(int generation) async {
    try {
      final audio = _audio;
      if (audio == null) return;
      if (_completed) {
        await audio.seek(Duration.zero);
        if (!_active(generation) || !_wantsPlay) return;
        _completed = false;
        _position = Duration.zero;
      }
      // play finishes on pause/completion, not on start.
      unawaited(audio.play().catchError((Object _) => _fail(generation)));
    } catch (_) {
      _fail(generation);
    }
  }

  Future<void> pause() async {
    if (_disposed) return;
    final generation = _generation;
    _wantsPlay = false;
    _playing = false;
    notifyListeners();
    try {
      await _audio?.pause();
    } catch (_) {
      _fail(generation);
    }
  }

  Future<void> toggle(Album album, Track track) =>
      isCurrent(album, track) && _wantsPlay ? pause() : play(album, track);

  void _fail(int generation) {
    if (!_active(generation) || _error != null) return;
    _error = 'Preview could not be played. Check your connection and retry.';
    _playing = false;
    _wantsPlay = false;
    _loading = false;
    _ready = false;
    _release();
    notifyListeners();
  }

  void _release() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    final audio = _audio;
    _audio = null;
    if (audio != null) {
      final prior = _releasing;
      final release = audio.dispose().catchError((Object _) {});
      _releasing = Future.wait([prior, release]).then((_) {});
    }
  }

  void stop() {
    if (_disposed) return;
    ++_generation;
    _release();
    _album = null;
    _track = null;
    _position = Duration.zero;
    _duration = previewLimit;
    _playing = _loading = _ready = _wantsPlay = _completed = false;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _release();
    super.dispose();
  }
}
