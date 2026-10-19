import 'dart:async';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../vision/best_frame_selector.dart';
import '../vision/camera_frame.dart';
import '../vision/frame_analyzer.dart';

enum LiveScannerState {
  idle,
  starting,
  running,
  permissionDenied,
  permissionPermanentlyDenied,

  /// No camera, or it failed to open. The scan page falls back to the
  /// system camera app.
  unavailable,
}

/// Live camera preview plus album-cover detection on sampled frames
/// (S2-09). Screens listen to it for [covers] and [state].
abstract class LiveScanner extends ChangeNotifier {
  LiveScannerState get state;

  /// The plugin controller for `CameraPreview`; `null` unless running.
  CameraController? get controller;

  /// Covers in the latest analysed frame, in sensor coordinates.
  List<CoverSnapshot> get covers;

  /// Best views of covers picked for recognition (S2-10), one per cover
  /// while it stays in view.
  Stream<CoverCapture> get captures;

  /// The camera's `sensorOrientation` in degrees.
  int get sensorDegrees;

  /// Width / height of the upright preview.
  double get previewAspect;

  /// Average analysis time per frame, for diagnostics.
  double get averageAnalysisMs;
  int get analysedFrames;

  /// Opens the camera. After the user refused camera access, this does
  /// not ask again; [requestAccess] does.
  Future<void> start();
  Future<void> stop();

  /// Asks for camera access again (the user tapped "Allow camera access"),
  /// then starts.
  Future<void> requestAccess();

  /// Stops analysing frames (for example while another page is on top)
  /// without closing the camera.
  bool get analysisPaused;
  set analysisPaused(bool value);

  /// Takes a full-resolution photo with the live camera. Returns the file
  /// path, or `null` when it failed.
  Future<String?> takePicture();
}

/// Stand-in for tests and devices without a usable camera.
class UnavailableLiveScanner extends LiveScanner {
  @override
  LiveScannerState get state => LiveScannerState.unavailable;
  @override
  CameraController? get controller => null;
  @override
  List<CoverSnapshot> get covers => const [];
  @override
  Stream<CoverCapture> get captures => const Stream.empty();
  @override
  int get sensorDegrees => 90;
  @override
  double get previewAspect => 3 / 4;
  @override
  double get averageAnalysisMs => 0;
  @override
  int get analysedFrames => 0;
  @override
  bool analysisPaused = false;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> requestAccess() async {}
  @override
  Future<String?> takePicture() async => null;
}

/// [LiveScanner] backed by the `camera` plugin. Frames are sampled at most
/// every [frameInterval] and analysed in a background isolate; frames that
/// arrive while the isolate is busy are dropped, so the preview never lags.
class CameraLiveScanner extends LiveScanner {
  CameraLiveScanner({this.frameInterval = const Duration(milliseconds: 200)});

  final Duration frameInterval;

  LiveScannerState _state = LiveScannerState.idle;
  CameraController? _controller;
  _AnalysisWorker? _worker;
  List<CoverSnapshot> _covers = const [];
  final _captures = StreamController<CoverCapture>.broadcast();
  bool _busy = false;
  bool _paused = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  int _frames = 0;
  int _totalMs = 0;

  /// Whether the camera should be open. Start and stop requests only set
  /// this; [_reconcile] then opens or closes the camera, one step at a
  /// time, until it matches. Lifecycle events can arrive in any order (a
  /// permission dialog pauses the app in the middle of a start), and the
  /// last request always wins.
  bool _wanted = false;
  bool _refused = false;
  Future<void>? _transition;

  @override
  LiveScannerState get state => _state;
  @override
  CameraController? get controller => _controller;
  @override
  List<CoverSnapshot> get covers => _covers;
  @override
  Stream<CoverCapture> get captures => _captures.stream;
  @override
  int get sensorDegrees => _controller?.description.sensorOrientation ?? 90;
  @override
  double get previewAspect {
    final size = _controller?.value.previewSize;
    if (size == null) return 3 / 4;
    // previewSize is reported in sensor orientation (landscape).
    final upright = sensorDegrees % 180 == 90;
    return upright ? size.height / size.width : size.width / size.height;
  }

  @override
  double get averageAnalysisMs => _frames == 0 ? 0 : _totalMs / _frames;
  @override
  int get analysedFrames => _frames;

  @override
  bool get analysisPaused => _paused;
  @override
  set analysisPaused(bool value) {
    if (_paused == value) return;
    _paused = value;
    if (value) {
      _covers = const [];
      _worker?.reset();
      notifyListeners();
    }
  }

  @override
  Future<void> start() {
    _wanted = true;
    return _reconcile();
  }

  @override
  Future<void> stop() {
    _wanted = false;
    return _reconcile();
  }

  @override
  Future<void> requestAccess() {
    _refused = false;
    return start();
  }

  Future<void> _reconcile() =>
      _transition ??= _settle().whenComplete(() => _transition = null);

  Future<void> _settle() async {
    while (true) {
      if (_wanted && _controller == null && !_refused) {
        if (!await _open()) return;
      } else if (!_wanted && _controller != null) {
        await _close();
      } else {
        return;
      }
    }
  }

  /// Returns false when the camera cannot be opened (no permission, no
  /// camera), so [_settle] stops trying until the user acts.
  Future<bool> _open() async {
    _setState(LiveScannerState.starting);
    final permission = await Permission.camera.request();
    if (permission.isPermanentlyDenied || !permission.isGranted) {
      _refused = true;
      _setState(
        permission.isPermanentlyDenied
            ? LiveScannerState.permissionPermanentlyDenied
            : LiveScannerState.permissionDenied,
      );
      return false;
    }
    if (!_wanted) {
      _setState(LiveScannerState.idle);
      return true;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setState(LiveScannerState.unavailable);
        return false;
      }
      final back = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      final controller = CameraController(
        back.isNotEmpty ? back.first : cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      _controller = controller;
      await controller.initialize();
      _worker ??= await _AnalysisWorker.spawn();
      await controller.startImageStream(_onImage);
      _setState(LiveScannerState.running);
      return true;
    } on CameraException catch (error) {
      debugPrint('Live camera unavailable: ${error.code}');
      await _disposeController();
      final denied = error.code == 'CameraAccessDenied';
      _refused = denied;
      _setState(
        denied
            ? LiveScannerState.permissionDenied
            : LiveScannerState.unavailable,
      );
      return false;
    }
  }

  Future<void> _close() async {
    await _disposeController();
    _covers = const [];
    _worker?.reset();
    _setState(LiveScannerState.idle);
  }

  void _onImage(CameraImage image) {
    if (_busy || _paused || image.planes.length < 3) return;
    final now = DateTime.now();
    if (now.difference(_lastFrame) < frameInterval) return;
    _lastFrame = now;
    _busy = true;
    final frame = _copyFrame(image, sensorDegrees);
    _worker!
        .analyze(frame)
        .then((analysis) {
          _frames++;
          _totalMs += analysis.elapsedMs;
          if (kDebugMode && _frames % 25 == 1) {
            debugPrint(
              'Live analysis: frame $_frames, ${image.width}x${image.height}, '
              '${analysis.elapsedMs} ms, ${analysis.covers.length} covers, '
              '${analysis.covers.where((c) => c.captured).length} captured',
            );
          }
          if (!_paused) {
            _covers = analysis.covers;
            analysis.captures.forEach(_captures.add);
            notifyListeners();
          }
        })
        .whenComplete(() => _busy = false);
  }

  @override
  Future<String?> takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    try {
      final photo = await controller.takePicture();
      return photo.path;
    } on CameraException catch (error) {
      debugPrint('Live capture failed: ${error.code}');
      return null;
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } on CameraException {
      // Already stopped.
    }
    await controller.dispose();
  }

  void _setState(LiveScannerState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposeController();
    _worker?.close();
    _captures.close();
    super.dispose();
  }
}

/// Copies the plugin's plane buffers, which are only valid during the
/// stream callback.
CameraFrame _copyFrame(CameraImage image, int rotationDegrees) {
  final y = image.planes[0];
  final u = image.planes[1];
  final v = image.planes[2];
  return CameraFrame(
    width: image.width,
    height: image.height,
    y: Uint8List.fromList(y.bytes),
    yRowStride: y.bytesPerRow,
    u: Uint8List.fromList(u.bytes),
    v: Uint8List.fromList(v.bytes),
    uvRowStride: u.bytesPerRow,
    uvPixelStride: u.bytesPerPixel ?? 1,
    rotationDegrees: rotationDegrees,
  );
}

/// A long-lived isolate that owns a [FrameAnalyzer], so tracking state
/// survives between frames.
class _AnalysisWorker {
  _AnalysisWorker._(this._isolate, this._commands, this._results);

  final Isolate _isolate;
  final SendPort _commands;
  final StreamIterator<Object?> _results;
  Future<void> _queue = Future.value();

  static Future<_AnalysisWorker> spawn() async {
    final fromWorker = ReceivePort();
    final isolate = await Isolate.spawn(_main, fromWorker.sendPort);
    final results = StreamIterator<Object?>(fromWorker);
    await results.moveNext();
    return _AnalysisWorker._(isolate, results.current! as SendPort, results);
  }

  Future<FrameAnalysis> analyze(CameraFrame frame) {
    final completer = Completer<FrameAnalysis>();
    _queue = _queue.then((_) async {
      _commands.send(frame);
      await _results.moveNext();
      completer.complete(_results.current! as FrameAnalysis);
    });
    return completer.future;
  }

  void reset() => _commands.send('reset');

  void close() {
    _commands.send(null);
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }

  static void _main(SendPort toMain) {
    final commands = ReceivePort();
    toMain.send(commands.sendPort);
    final analyzer = FrameAnalyzer();
    commands.listen((message) {
      if (message == null) {
        commands.close();
      } else if (message == 'reset') {
        analyzer.reset();
      } else if (message is CameraFrame) {
        toMain.send(analyzer.analyze(message));
      }
    });
  }
}
