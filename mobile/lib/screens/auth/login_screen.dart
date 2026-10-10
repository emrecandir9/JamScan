import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../routing/app_routes.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Sign in and register (wireframe 22, UC-01). Pops with `true` once
/// signed in, `false` for "Continue as guest".
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.args});

  final LoginArgs args;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.args.register ? 1 : 0,
  );
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  AuthError? _error;
  bool _busy = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _registering => _tabs.index == 1;

  void _onTabChanged() {
    if (_error != null) {
      setState(() => _error = null);
    } else {
      setState(() {});
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final auth = AppScope.of(context).auth;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });

    final error = _registering
        ? await auth.register(
            displayName: _name.text,
            email: _email.text,
            password: _password.text,
          )
        : await auth.signIn(email: _email.text, password: _password.text);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) {
      final name = auth.user?.displayName ?? '';
      showAppSnackBar(messenger, 'Signed in as $name');
      navigator.pop(true);
    }
  }

  void _forgotPassword() {
    showAppSnackBar(
      ScaffoldMessenger.of(context),
      "Password reset isn't available while accounts are simulated.",
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.surfaceStrong,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.album,
                  size: 48,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'JamSCAN',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Sign in'),
                Tab(text: 'Register'),
              ],
            ),
            const SizedBox(height: 24),
            if (_registering) ...[
              TextField(
                key: const Key('login.name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: AppInputs.outlined('Display name'),
              ),
              const SizedBox(height: 20),
            ],
            TextField(
              key: const Key('login.email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: AppInputs.outlined('Email'),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('login.password'),
              controller: _password,
              obscureText: !_showPassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              autofillHints: const [AutofillHints.password],
              decoration: AppInputs.outlined('Password').copyWith(
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error.message,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ],
            if (!_registering)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _forgotPassword,
                  child: const Text('Forgot password?'),
                ),
              )
            else
              const SizedBox(height: 16),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('login.submit'),
              onPressed: _busy ? null : _submit,
              child: Text(_registering ? 'Create account' : 'Sign in'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Continue as guest'),
            ),
            const SizedBox(height: 32),
            Text(
              'Accounts are simulated locally in this version.\n'
              'Demo account: ${AuthController.demoEmail} · '
              '${AuthController.demoPassword}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
