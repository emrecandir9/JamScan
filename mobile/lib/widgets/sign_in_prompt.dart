import 'package:flutter/material.dart';

import '../routing/app_navigation.dart';

/// Dialog shown when a guest tries something that needs an account (13).
///
/// Completes with `true` when the user signed in from it.
Future<bool> showSignInPrompt(
  BuildContext context, {
  String title = 'Sign in to save albums',
  String message =
      'Collections, wishlists and scan history need an account. '
      'Scanning and previews stay available without one.',
}) async {
  final wantsSignIn = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sign in'),
        ),
      ],
    ),
  );
  if (wantsSignIn != true || !context.mounted) {
    return false;
  }
  final signedIn = await AppNav.signIn(context);
  return signedIn ?? false;
}
