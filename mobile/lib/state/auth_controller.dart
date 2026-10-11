import 'package:flutter/foundation.dart';

import '../models/app_user.dart';

enum AuthError {
  invalidCredentials,
  emailTaken,
  invalidEmail,
  weakPassword,
  missingName,
}

extension AuthErrorMessage on AuthError {
  String get message => switch (this) {
    AuthError.invalidCredentials => 'Incorrect email or password',
    AuthError.emailTaken => 'An account with this email already exists',
    AuthError.invalidEmail => 'Enter a valid email address',
    AuthError.weakPassword => 'Use at least 8 characters',
    AuthError.missingName => 'Enter a display name',
  };
}

class _Account {
  _Account(this.user, this.password);

  AppUser user;
  final String password;
}

/// Mock authentication state. Accounts live in memory only.
///
/// A guest (no user) can scan and play previews. Saving albums, lists and
/// history need an account (UC-01). Replace with real authentication later;
/// screens only depend on [user], [isSignedIn] and the methods below.
class AuthController extends ChangeNotifier {
  AuthController({bool signedInAsDemo = false}) {
    _accounts[demoEmail] = _Account(
      const AppUser(displayName: 'Demo Collector', email: demoEmail),
      demoPassword,
    );
    if (signedInAsDemo) {
      _user = _accounts[demoEmail]!.user;
    }
  }

  static const demoEmail = 'demo@jamscan.app';
  static const demoPassword = 'jamscan123';
  static const minPasswordLength = 8;

  final Map<String, _Account> _accounts = {};
  AppUser? _user;

  AppUser? get user => _user;
  bool get isSignedIn => _user != null;

  Future<AuthError?> signIn({
    required String email,
    required String password,
  }) async {
    final account = _accounts[_normalise(email)];
    if (account == null || account.password != password) {
      return AuthError.invalidCredentials;
    }
    _user = account.user;
    notifyListeners();
    return null;
  }

  Future<AuthError?> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final name = displayName.trim();
    final key = _normalise(email);
    if (name.isEmpty) {
      return AuthError.missingName;
    }
    if (!_looksLikeEmail(key)) {
      return AuthError.invalidEmail;
    }
    if (password.length < minPasswordLength) {
      return AuthError.weakPassword;
    }
    if (_accounts.containsKey(key)) {
      return AuthError.emailTaken;
    }
    final account = _Account(AppUser(displayName: name, email: key), password);
    _accounts[key] = account;
    _user = account.user;
    notifyListeners();
    return null;
  }

  void signOut() {
    if (_user == null) {
      return;
    }
    _user = null;
    notifyListeners();
  }

  void updateDisplayName(String displayName) {
    final user = _user;
    final name = displayName.trim();
    if (user == null || name.isEmpty) {
      return;
    }
    final updated = user.copyWith(displayName: name);
    _accounts[user.email]?.user = updated;
    _user = updated;
    notifyListeners();
  }

  /// Removes the current account and signs out.
  void deleteAccount() {
    final user = _user;
    if (user == null) {
      return;
    }
    _accounts.remove(user.email);
    _user = null;
    notifyListeners();
  }

  static String _normalise(String email) => email.trim().toLowerCase();

  static bool _looksLikeEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }
}
