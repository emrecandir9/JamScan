import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/album.dart';
import '../screens/scan/scan_flow_screen.dart';
import '../state/shell_controller.dart';
import 'app_routes.dart';

/// Typed navigation helpers. Screens call these instead of using route
/// names directly, so the result types stay in one place.
abstract final class AppNav {
  /// Shows [tab] and closes any pages pushed on top of the shell.
  static void switchTab(BuildContext context, AppTab tab) {
    AppScope.of(context).shell.tab = tab;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Opens the Scan tab with [album] shown as the result.
  static void showResult(BuildContext context, Album album) {
    AppScope.of(context).shell.showResult(album);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  static Future<ScanFlowResult?> identify(
    BuildContext context, {
    String? imagePath,
  }) {
    return Navigator.of(context).pushNamed<ScanFlowResult>(
      AppRoutes.scanFlow,
      arguments: ScanFlowArgs(imagePath: imagePath),
    );
  }

  /// Opens manual search. Completes with the release the user picked.
  static Future<Album?> search(
    BuildContext context, {
    String initialQuery = '',
    bool afterFailedScan = false,
  }) {
    return Navigator.of(context).pushNamed<Album>(
      AppRoutes.manualSearch,
      arguments: ManualSearchArgs(
        initialQuery: initialQuery,
        afterFailedScan: afterFailedScan,
      ),
    );
  }

  static Future<void> openAlbum(
    BuildContext context,
    Album album, {
    AppTab tab = AppTab.scan,
  }) {
    return Navigator.of(context).pushNamed<void>(
      AppRoutes.albumDetails,
      arguments: AlbumDetailsArgs(album, tab: tab),
    );
  }

  static Future<void> openList(BuildContext context, String listId) {
    return Navigator.of(
      context,
    ).pushNamed<void>(AppRoutes.listDetail, arguments: ListDetailArgs(listId));
  }

  /// Opens sign in or register. Completes with `true` once signed in.
  static Future<bool?> signIn(BuildContext context, {bool register = false}) {
    return Navigator.of(context).pushNamed<bool>(
      AppRoutes.login,
      arguments: LoginArgs(register: register),
    );
  }

  static Future<void> openSettings(BuildContext context) {
    return Navigator.of(context).pushNamed<void>(AppRoutes.settings);
  }
}
