/// Domain representation of an authenticated user.
///
/// Decoupled from Supabase's `User` so the rest of the app never depends on a
/// specific auth provider (repository pattern — see brief §4, §14 vendor
/// lock-in mitigation).
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String email;
  final String? displayName;
  final String? avatarUrl;

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.id == id &&
      other.email == email &&
      other.displayName == displayName &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(id, email, displayName, avatarUrl);
}
