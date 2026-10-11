import 'package:flutter/material.dart';

import '../models/album.dart';
import '../screens/album/album_details_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/library/list_detail_screen.dart';
import '../screens/scan/scan_flow_screen.dart';
import '../screens/search/manual_search_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/shell/app_shell.dart';
import '../state/shell_controller.dart';

/// Route names. See docs/Navigational_Diagram.drawio for the flow.
abstract final class AppRoutes {
  /// Tab shell: Scan (camera), Library and Profile.
  static const shell = '/';

  /// Loading, retake prompt, candidate selection and not recognised.
  static const scanFlow = '/scan/identify';
  static const manualSearch = '/search';
  static const albumDetails = '/album';
  static const listDetail = '/library/list';
  static const login = '/login';
  static const settings = '/settings';
}

class ScanFlowArgs {
  const ScanFlowArgs({this.imagePath});

  /// Photo taken or imported. `null` shows a cover placeholder.
  final String? imagePath;
}

class ManualSearchArgs {
  const ManualSearchArgs({
    this.initialQuery = '',
    this.afterFailedScan = false,
  });

  final String initialQuery;

  /// The cover was not recognised before the user searched.
  final bool afterFailedScan;
}

class AlbumDetailsArgs {
  const AlbumDetailsArgs(this.album, {this.tab = AppTab.scan});

  final Album album;

  /// Tab highlighted in the taskbar.
  final AppTab tab;
}

class ListDetailArgs {
  const ListDetailArgs(this.listId);

  final String listId;
}

class LoginArgs {
  const LoginArgs({this.register = false});

  /// Open on the Register tab.
  final bool register;
}

/// Builds routes for [MaterialApp.onGenerateRoute].
///
/// Each route is created with the result type its screen pops with, so
/// `Navigator.pushNamed<T>` in [AppNav] gets a correctly typed future.
abstract final class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final args = settings.arguments;
    switch (settings.name) {
      case AppRoutes.shell:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => const AppShell(),
        );
      case AppRoutes.scanFlow:
        return MaterialPageRoute<ScanFlowResult>(
          settings: settings,
          builder: (context) => ScanFlowScreen(
            args: args is ScanFlowArgs ? args : const ScanFlowArgs(),
          ),
        );
      case AppRoutes.manualSearch:
        return MaterialPageRoute<Album>(
          settings: settings,
          builder: (context) => ManualSearchScreen(
            args: args is ManualSearchArgs ? args : const ManualSearchArgs(),
          ),
        );
      case AppRoutes.albumDetails:
        if (args is AlbumDetailsArgs) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (context) => AlbumDetailsScreen(args: args),
          );
        }
      case AppRoutes.listDetail:
        if (args is ListDetailArgs) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (context) => ListDetailScreen(listId: args.listId),
          );
        }
      case AppRoutes.login:
        return MaterialPageRoute<bool>(
          settings: settings,
          fullscreenDialog: true,
          builder: (context) =>
              LoginScreen(args: args is LoginArgs ? args : const LoginArgs()),
        );
      case AppRoutes.settings:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => const SettingsScreen(),
        );
    }
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (context) => _UnknownRouteScreen(name: settings.name),
    );
  }
}

class _UnknownRouteScreen extends StatelessWidget {
  const _UnknownRouteScreen({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'This page does not exist: ${name ?? 'unknown'}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
