import 'package:just_audio/just_audio.dart';

/// One source per instance: a cancelled load cannot affect a new track.
abstract class PreviewAudio {
  Stream<PlayerState> get states;
  Stream<Duration> get positions;
  Stream<Duration?> get durations;
  Stream<Object> get errors;
  Future<void> load(String url, Duration limit);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

class JustAudioPreview implements PreviewAudio {
  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<PlayerState> get states => _player.playerStateStream;
  @override
  Stream<Duration> get positions => _player.positionStream;
  @override
  Stream<Duration?> get durations => _player.durationStream;
  @override
  Stream<Object> get errors => _player.errorStream;

  @override
  Future<void> load(String url, Duration limit) async {
    await _player.setAudioSource(
      ClippingAudioSource(
        child: AudioSource.uri(Uri.parse(url)),
        start: Duration.zero,
        end: limit,
      ),
    );
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> dispose() => _player.dispose();
}
