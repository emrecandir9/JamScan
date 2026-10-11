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

class _JamScanAppState extends State<JamScanApp> {
  late final AppDependencies _dependencies;

  @override
  void initState() {
    super.initState();
    _dependencies = widget.dependencies ?? AppDependencies();
  }

  @override
  void dispose() {
    _dependencies.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      dependencies: _dependencies,
      child: MaterialApp(
        title: 'JamSCAN',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        initialRoute: AppRoutes.shell,
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
  }
}
