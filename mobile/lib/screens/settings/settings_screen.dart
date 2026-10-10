import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/album.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../library/list_dialogs.dart';

/// Settings (wireframes 23a and 23b, UC-15).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _editDisplayName(BuildContext context) async {
    final auth = AppScope.of(context).auth;
    final name = await showDialog<String>(
      context: context,
      builder: (context) =>
          _DisplayNameDialog(initial: auth.user?.displayName ?? ''),
    );
    if (name != null) {
      auth.updateDisplayName(name);
    }
  }

  Future<void> _pickDefaultFormat(BuildContext context) async {
    final settings = AppScope.of(context).settings;
    final format = await showModalBottomSheet<MediaFormat>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in MediaFormat.values)
              ListTile(
                title: Text(option.label),
                trailing: option == settings.defaultFormat
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(context).pop(option),
              ),
          ],
        ),
      ),
    );
    if (format != null) {
      settings.defaultFormat = format;
    }
  }

  Future<void> _clearHistory(BuildContext context) async {
    final history = AppScope.of(context).history;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmAction(
      context,
      title: 'Clear scan history?',
      message: 'All scans and searches will be removed from this device.',
      confirmLabel: 'Clear',
    );
    if (!confirmed) return;
    history.clear();
    showAppSnackBar(messenger, 'Scan history cleared');
  }

  void _signOut(BuildContext context) {
    final deps = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    deps.player.stop();
    deps.auth.signOut();
    showAppSnackBar(messenger, 'Signed out');
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final deps = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await confirmAction(
      context,
      title: 'Delete your account?',
      message:
          'Your collections, wishlists and scan history will be permanently '
          'deleted from this device.',
      confirmLabel: 'Delete account',
    );
    final user = deps.auth.user;
    if (!confirmed || user == null) return;
    navigator.pop();
    deps.player.stop();
    deps.library.deleteDataFor(user.email);
    deps.history.deleteDataFor(user.email);
    deps.auth.deleteAccount();
    showAppSnackBar(messenger, 'Account deleted');
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        title: const Text('Settings'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([deps.auth, deps.settings]),
        builder: (context, _) {
          final user = deps.auth.user;
          return ListView(
            children: [
              const _Section('Account'),
              _Row(
                title: 'Display name',
                value: user?.displayName ?? '',
                onTap: () => _editDisplayName(context),
              ),
              _Row(
                title: 'Change password',
                chevron: true,
                onTap: () => showAppSnackBar(
                  ScaffoldMessenger.of(context),
                  "Passwords can't be changed while accounts are simulated.",
                ),
              ),
              _Row(title: 'Email', value: user?.email ?? ''),
              const _Section('Preferences'),
              _Row(
                title: 'Default format',
                value: deps.settings.defaultFormat.label,
                onTap: () => _pickDefaultFormat(context),
              ),
              SwitchListTile(
                key: const Key('settings.autoplay'),
                title: const Text('Autoplay top track'),
                value: deps.settings.autoplayTopTrack,
                onChanged: (value) => deps.settings.autoplayTopTrack = value,
              ),
              const Divider(indent: AppSpacing.page, height: 1),
              _Row(
                title: 'Clear scan history',
                chevron: true,
                onTap: () => _clearHistory(context),
              ),
              const SizedBox(height: 24),
              _Row(
                title: 'Log out',
                chevron: true,
                onTap: () => _signOut(context),
              ),
              _Row(
                title: 'Delete account',
                chevron: true,
                onTap: () => _deleteAccount(context),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 24, 20, 4),
      child: SectionLabel(title),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    this.value,
    this.chevron = false,
    this.onTap,
  });

  final String title;
  final String? value;
  final bool chevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final Widget? trailing;
    if (chevron) {
      trailing = const Icon(Icons.chevron_right);
    } else if (value != null) {
      trailing = Text(
        value,
        style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
      );
    } else {
      trailing = null;
    }
    return Column(
      children: [
        ListTile(
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          trailing: trailing,
          onTap: onTap,
        ),
        const Divider(indent: AppSpacing.page, height: 1),
      ],
    );
  }
}

class _DisplayNameDialog extends StatefulWidget {
  const _DisplayNameDialog({required this.initial});

  final String initial;

  @override
  State<_DisplayNameDialog> createState() => _DisplayNameDialogState();
}

class _DisplayNameDialogState extends State<_DisplayNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Display name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: AppInputs.outlined('Display name'),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
