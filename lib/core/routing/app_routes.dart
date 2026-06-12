/// Centralised route paths and names for go_router (brief §5.1, §6.1 web URLs).
abstract class AppRoutes {
  AppRoutes._();

  static const String onboarding = '/onboarding';
  static const String auth = '/auth';
  static const String home = '/';
  static const String tree = '/tree';
  static const String records = '/records';
  static const String collab = '/collab';
  static const String profile = '/profile';

  /// Full-screen person profile, pushed over the shell: `/person/:id`.
  static const String person = '/person';
}
