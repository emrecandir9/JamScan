import 'dart:async';

import 'package:flutter/widgets.dart';

import 'data/local/app_database.dart';
import 'data/release_repository.dart';
import 'services/camera_capture_service.dart';
import 'services/catalog_service.dart';
import 'services/gallery_import_service.dart';
import 'services/live_scanner.dart';
import 'services/queued_recognition_service.dart';
import 'services/recognition_api.dart';
import 'services/recognition_service.dart';
import 'services/release_api.dart';
import 'services/release_details_service.dart';
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

/// [apiUrl] as a base URI that endpoint paths resolve against, or null when
/// no backend is configured.
Uri? configuredBackendUrl([String value = apiUrl]) {
  final text = value.trim();
  if (text.isEmpty) return null;
  // A trailing slash keeps a path prefix (`http://host/api/`) when
  // resolving `recognitions` or `releases/...` against it.
  return Uri.parse(text.endsWith('/') ? text : '$text/');
}

/// Services and app-wide state shared by every screen.
///
/// With a backend URL ([apiUrl], or [backendUrl] in tests) recognition,
/// manual search and release details all use the backend, and release
/// metadata is cached in the local database (S2-07). Without one the app
/// runs on the offline mocks, so every screen can still be demonstrated.
///
/// Pass replacements for any service to swap in a fake in tests.
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
    ReleaseDetailsService? releaseDetails,
    Uri? backendUrl,
    AppDatabase? database,
  }) : auth = auth ?? AuthController(),
       camera = camera ?? CameraCaptureService(),
       gallery = gallery ?? GalleryImportService(),
       settings = settings ?? SettingsController(),
       player = player ?? PreviewPlayer(),
       liveScanner = liveScanner ?? CameraLiveScanner(),
       shell = ShellController() {
    final url = backendUrl ?? configuredBackendUrl();
    final releaseApi = url == null ? null : HttpReleaseApi(url);

    if (releaseDetails == null && releaseApi != null) {
      _ownsDatabase = database == null;
      this.database = database ?? AppDatabase();
    } else {
      this.database = database;
    }
    final db = this.database;
    this.releaseDetails =
        releaseDetails ??
        (releaseApi == null || db == null
            ? const BasicReleaseDetails()
            : RepositoryReleaseDetails(
                ReleaseRepository(db, releaseApi.release),
              ));
    this.catalog =
        catalog ??
        (releaseApi == null
            ? MockCatalogService()
            : HttpCatalogService(releaseApi));
    this.session =
        session ??
        RecognitionSession(
          api: url == null ? MockRecognitionApi() : HttpRecognitionApi(url),
          details: this.releaseDetails,
        );
    // Without a backend the scripted mock keeps every scan-flow screen
    // reachable; with one, photos share the live recognition queue.
    this.recognition =
        recognition ??
        (url == null
            ? MockRecognitionService()
            : QueuedRecognitionService(this.session));
    library = LibraryStore(this.auth);
    history = HistoryStore(this.auth);
  }

  final AuthController auth;
  final CameraCaptureService camera;
  final GalleryImportService gallery;
  late final RecognitionService recognition;
  late final CatalogService catalog;

  /// Loads full release details (Discogs metadata and previews) for
  /// recognised releases and selected search hits.
  late final ReleaseDetailsService releaseDetails;

  /// Local cache of fetched release metadata; null without a backend.
  late final AppDatabase? database;
  bool _ownsDatabase = false;
  final SettingsController settings;
  final PreviewPlayer player;
  final LiveScanner liveScanner;

  /// Recognition jobs of the current scanning session (S2-11).
  late final RecognitionSession session;
  final ShellController shell;
  late final LibraryStore library;
  late final HistoryStore history;

  void dispose() {
    if (_ownsDatabase) {
      unawaited(database?.close());
    }
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
