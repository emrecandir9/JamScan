import 'package:flutter/widgets.dart';

import 'services/camera_capture_service.dart';
import 'services/catalog_service.dart';
import 'services/gallery_import_service.dart';
import 'services/live_scanner.dart';
import 'services/queued_recognition_service.dart';
import 'services/recognition_api.dart';
import 'services/recognition_service.dart';
import 'state/auth_controller.dart';
import 'state/history_store.dart';
import 'state/library_store.dart';
import 'state/preview_player.dart';
import 'state/recognition_session.dart';
import 'state/settings_controller.dart';
import 'state/shell_controller.dart';

/// Base URL of the JamSCAN backend, from
/// `--dart-define=JAMSCAN_API_URL=http://10.0.2.2:8000` (the host machine as
/// seen from the Android emulator). Empty means offline mock services.
const apiUrl = String.fromEnvironment('JAMSCAN_API_URL');

/// Services and app-wide state shared by every screen.
///
/// Pass replacements for any of them to swap a mock for a real
/// implementation, or a fake in tests.
class AppDependencies {
  AppDependencies({
    AuthController? auth,
    CameraCaptureService? camera,
    GalleryImportService? gallery,
    RecognitionService? recognition,
    CatalogService? catalog,
    SettingsController? settings,
    PreviewPlayer? player,
    LiveScanner? liveScanner,
    RecognitionSession? session,
  }) : auth = auth ?? AuthController(),
       camera = camera ?? CameraCaptureService(),
       gallery = gallery ?? GalleryImportService(),
       catalog = catalog ?? MockCatalogService(),
       settings = settings ?? SettingsController(),
       player = player ?? PreviewPlayer(),
       liveScanner = liveScanner ?? CameraLiveScanner(),
       session =
           session ??
           RecognitionSession(
             api: apiUrl.isEmpty
                 ? MockRecognitionApi()
                 : HttpRecognitionApi(Uri.parse(apiUrl)),
           ),
       shell = ShellController() {
    // Without a backend the scripted mock keeps every scan-flow screen
    // reachable; with one, photos share the live recognition queue.
    this.recognition =
        recognition ??
        (apiUrl.isEmpty
            ? MockRecognitionService()
            : QueuedRecognitionService(this.session));
    library = LibraryStore(this.auth);
    history = HistoryStore(this.auth);
  }

  final AuthController auth;
  final CameraCaptureService camera;
  final GalleryImportService gallery;
  late final RecognitionService recognition;
  final CatalogService catalog;
  final SettingsController settings;
  final PreviewPlayer player;
  final LiveScanner liveScanner;

  /// Recognition jobs of the current scanning session (S2-11).
  final RecognitionSession session;
  final ShellController shell;
  late final LibraryStore library;
  late final HistoryStore history;

  void dispose() {
    liveScanner.dispose();
    session.dispose();
    player.dispose();
    library.dispose();
    history.dispose();
    settings.dispose();
    shell.dispose();
    auth.dispose();
  }
}

/// Makes [AppDependencies] available to every route.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.dependencies, required super.child});

  final AppDependencies dependencies;

  /// Reads the dependencies without subscribing to rebuilds. Screens listen
  /// to the individual controllers with `ListenableBuilder` instead.
  static AppDependencies of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this context.');
    return scope!.dependencies;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) {
    return dependencies != oldWidget.dependencies;
  }
}
