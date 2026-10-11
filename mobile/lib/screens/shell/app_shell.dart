import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../state/shell_controller.dart';
import '../library/library_screen.dart';
import '../profile/profile_screen.dart';
import '../scan/scan_screen.dart';

/// Hosts the three tabs and keeps their state while switching.
///
/// Each tab draws its own taskbar, because the Scan tab uses
/// History / Scan / Search while the others use Profile / Scan / Library.
/// The system back button returns to the Scan tab before leaving the app.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) {
        return PopScope(
          canPop: shell.tab == AppTab.scan,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              shell.tab = AppTab.scan;
            }
          },
          child: IndexedStack(
            index: shell.tab.index,
            // Every tab's Scaffold shows a shared snack bar. Only the visible
            // tab may take part in hero transitions, otherwise the identical
            // snack bar heroes collide when a route is pushed or popped.
            children: [
              for (final (index, tab) in const [
                ScanScreen(),
                LibraryScreen(),
                ProfileScreen(),
              ].indexed)
                HeroMode(enabled: index == shell.tab.index, child: tab),
            ],
          ),
        );
      },
    );
  }
}
