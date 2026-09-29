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
    this.bio,
    this.createdAt,
    this.lastSignInAt,
  });

  final String id;
  final String email;
  final String? displayName;
  final String? avatarUrl;

  /// Short free-text "About me" — stored in Supabase Auth user_metadata
  /// (no separate `profiles` table exists), same as [displayName]/[avatarUrl].
  final String? bio;

  /// Account creation / most recent sign-in, straight from Supabase Auth
  /// (not our own data) — powers the "Member since" / "Last signed in" row.
  final DateTime? createdAt;
  final DateTime? lastSignInAt;

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.id == id &&
      other.email == email &&
      other.displayName == displayName &&
      other.avatarUrl == avatarUrl &&
      other.bio == bio &&
      other.createdAt == createdAt &&
      other.lastSignInAt == lastSignInAt;

  @override
  int get hashCode =>
      Object.hash(id, email, displayName, avatarUrl, bio, createdAt, lastSignInAt);
}
