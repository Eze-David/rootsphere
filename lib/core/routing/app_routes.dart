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

  /// Admin-only "Contact us" inbox, pushed over the shell: `/admin/support`.
  static const String supportMessages = '/admin/support';

  /// Admin-only Digital Records Repository (curated civil/historical records
  /// catalogue), pushed over the shell: `/admin/archive`.
  static const String archiveRepository = '/admin/archive';

  /// Public legal documents — reachable standalone (signed out, not
  /// onboarded) so they work as store-listing URLs (Play Console, App Store
  /// Connect), not just as an in-app push from the sign-up/footer links.
  static const String privacyPolicy = '/privacy-policy';
  static const String termsOfService = '/terms-of-service';

  /// Paystack's post-checkout `callback_url` lands here — must be a real
  /// page on our own domain, not a Supabase Edge Function URL: Supabase's
  /// function gateway force-overrides Content-Type to text/plain (plus a
  /// sandboxed CSP) on every function response, specifically to stop
  /// *.supabase.co from being used to host arbitrary HTML. Reachable
  /// standalone like the legal docs above (donor may not be signed in).
  static const String donationThankYou = '/donation-thank-you';
}
