import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'routing/app_routes.dart';
import 'theme/app_theme.dart';

class JamScanApp extends StatefulWidget {
  const JamScanApp({super.key, this.dependencies});

  /// Services and state for the app. Defaults use the mock services.
  ///
  /// The app takes ownership and disposes them when it is removed.
  final AppDependencies? dependencies;

  @override
  State<JamScanApp> createState() => _JamScanAppState();
}

class _JamScanAppState extends State<JamScanApp> with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  String? _lastPlayerError;
  late final AppDependencies _dependencies;

  @override
  void initState() {
    super.initState();
    _dependencies = widget.dependencies ?? AppDependencies();
    WidgetsBinding.instance.addObserver(this);
    _dependencies.player.addListener(_onPlayerChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dependencies.player.removeListener(_onPlayerChanged);
    _dependencies.dispose();
    super.dispose();
  }

  void _onPlayerChanged() {
    final error = _dependencies.player.error;
    if (error != null && error != _lastPlayerError) {
      _messenger.currentState?.showSnackBar(SnackBar(content: Text(error)));
    }
    _lastPlayerError = error;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _dependencies.player.pause();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      dependencies: _dependencies,
      child: MaterialApp(
        title: 'JamSCAN',
        scaffoldMessengerKey: _messenger,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        initialRoute: AppRoutes.shell,
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
  }
}
