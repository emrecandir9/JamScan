/// The signed-in user. Accounts are simulated locally for now.
class AppUser {
  const AppUser({required this.displayName, required this.email});

  final String displayName;
  final String email;

  AppUser copyWith({String? displayName}) {
    return AppUser(displayName: displayName ?? this.displayName, email: email);
  }
}
