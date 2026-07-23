/// Centralised route paths and names for go_router (brief §5.1, §6.1 web URLs).
abstract class AppRoutes {
  AppRoutes._();

  static const String onboarding = '/onboarding';
  static const String auth = '/auth';
  static const String resetPassword = '/reset-password';
  static const String home = '/';
  static const String tree = '/tree';
  static const String records = '/records';
  static const String collab = '/collab';
  static const String profile = '/profile';

  /// Full-screen person profile, pushed over the shell: `/person/:id`.
  static const String person = '/person';

  /// Full-screen record detail, pushed over the shell: `/record/:id`.
  static const String record = '/record';

  /// Full-screen hints list (Phase 4), pushed over the shell: `/hints`.
  static const String hints = '/hints';

  /// Full-screen notifications list, pushed over the shell: `/notifications`.
  static const String notifications = '/notifications';

  /// Admin-only Finder/Indexer application review queue, pushed over the
  /// shell: `/admin/verifications`.
  static const String roleVerificationReview = '/admin/verifications';

  /// Admin-only queue of opportunities sent directly to the company, pushed
  /// over the shell: `/admin/company-requests`.
  static const String companyRequests = '/admin/company-requests';

  /// Admin-only queue of Finder/Indexer submissions awaiting company review,
  /// pushed over the shell: `/admin/submissions`.
  static const String submissionReview = '/admin/submissions';
}
