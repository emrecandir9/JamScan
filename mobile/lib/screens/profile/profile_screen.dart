import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/app_user.dart';
import '../../routing/app_navigation.dart';
import '../../state/shell_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/taskbars.dart';
import '../history/history_sheet.dart';

/// Profile tab (21a signed in, 21b guest).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([deps.auth, deps.library, deps.history]),
          builder: (context, _) {
            final user = deps.auth.user;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Profile',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                        if (user != null)
                          IconButton(
                            tooltip: 'Settings',
                            icon: const Icon(Icons.settings_outlined),
                            onPressed: () => AppNav.openSettings(context),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: user == null
                      ? const _GuestProfile()
                      : _SignedInProfile(user: user),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: const MainTaskbar(current: AppTab.profile),
    );
  }
}

class _GuestProfile extends StatelessWidget {
  const _GuestProfile();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.person_outline,
      title: "You're browsing as a guest",
      message:
          'Scanning and previews work without an account. Sign in to save '
          'albums and keep your history.',
      actions: [
        FilledButton(
          onPressed: () => AppNav.signIn(context),
          child: const Text('Sign in'),
        ),
        OutlinedButton(
          onPressed: () => AppNav.signIn(context, register: true),
          child: const Text('Create account'),
        ),
      ],
    );
  }
}

class _SignedInProfile extends StatelessWidget {
  const _SignedInProfile({required this.user});

  final AppUser user;

  Future<void> _openHistory(BuildContext context) async {
    final album = await showHistorySheet(context);
    if (album == null || !context.mounted) return;
    AppNav.showResult(context, album);
  }

  void _signOut(BuildContext context) {
    final deps = AppScope.of(context);
    deps.player.stop();
    deps.auth.signOut();
    showAppSnackBar(ScaffoldMessenger.of(context), 'Signed out');
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 112,
            height: 112,
            decoration: const BoxDecoration(
              color: AppColors.surfaceStrong,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_outline,
              size: 56,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          user.displayName,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        Text(
          user.email,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                _Stat(value: deps.library.ownedCount, label: 'Owned'),
                const VerticalDivider(width: 1),
                _Stat(value: deps.library.wishlistCount, label: 'Wishlist'),
                const VerticalDivider(width: 1),
                _Stat(value: deps.history.scanCount, label: 'Scans'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _MenuRow(
          icon: Icons.history,
          label: 'Scan & search history',
          onTap: () => _openHistory(context),
        ),
        _MenuRow(
          icon: Icons.view_week_outlined,
          label: 'Manage lists',
          onTap: () => AppNav.switchTab(context, AppTab.library),
        ),
        _MenuRow(
          icon: Icons.settings_outlined,
          label: 'Settings',
          onTap: () => AppNav.openSettings(context),
        ),
        _MenuRow(
          icon: Icons.logout,
          label: 'Log out',
          onTap: () => _signOut(context),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon),
          title: Text(label, style: Theme.of(context).textTheme.titleMedium),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
        const Divider(indent: 72, height: 1),
      ],
    );
  }
}
