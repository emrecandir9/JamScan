import 'dart:async';

import 'package:camera/camera.dart';
import 'package:jamscan/services/live_scanner.dart';
import 'package:jamscan/vision/best_frame_selector.dart';
import 'package:jamscan/vision/frame_analyzer.dart';

/// A live scanner without a camera, whose state tests can set.
class FakeLiveScanner extends LiveScanner {
  FakeLiveScanner({this.startsAs = LiveScannerState.running});

  /// The state [start] moves to.
  LiveScannerState startsAs;
  String? picturePath = '/nonexistent/jamscan-live-photo.jpg';

  LiveScannerState _state = LiveScannerState.idle;
  List<CoverSnapshot> _covers = const [];
  int startCalls = 0;
  int stopCalls = 0;
  int pictureCalls = 0;

  @override
  LiveScannerState get state => _state;
  @override
  CameraController? get controller => null;
  @override
  List<CoverSnapshot> get covers => _covers;
  set covers(List<CoverSnapshot> value) {
    _covers = value;
    notifyListeners();
  }

  final captureController = StreamController<CoverCapture>.broadcast();

  @override
  Stream<CoverCapture> get captures => captureController.stream;

  @override
  int get sensorDegrees => 90;
  @override
  double get previewAspect => 9 / 16;
  @override
  double get averageAnalysisMs => 0;
  @override
  int get analysedFrames => 0;
  @override
  bool analysisPaused = false;

  @override
  Future<void> start() async {
    startCalls++;
    _state = startsAs;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (_state == LiveScannerState.running) {
      _state = LiveScannerState.idle;
      notifyListeners();
    }
  }

  int accessRequests = 0;

  @override
  Future<void> requestAccess() async {
    accessRequests++;
    await start();
  }

  @override
  Future<String?> takePicture() async {
    pictureCalls++;
    return picturePath;
  }
}
