import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/auth_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/collab/presentation/screens/opportunities_screen.dart';
import '../../features/collab/presentation/screens/company_requests_screen.dart';
import '../../features/collab/presentation/screens/role_verification_review_screen.dart';
import '../../features/collab/presentation/screens/submission_review_screen.dart';
import '../../features/hints/presentation/screens/hints_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/onboarding/presentation/providers/onboarding_provider.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/records/domain/entities/record.dart';
import '../../features/records/presentation/screens/historical_records_search_screen.dart';
import '../../features/records/presentation/screens/record_detail_screen.dart';
import '../../features/records/presentation/screens/records_screen.dart';
import '../../features/tree/presentation/screens/person_profile_screen.dart';
import '../../features/tree/presentation/screens/tree_screen.dart';
import '../../shared/widgets/home_shell.dart';
import '../../shared/widgets/placeholder_screen.dart';
import 'app_routes.dart';
import 'go_router_refresh_stream.dart';
import 'last_tab_provider.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Application router with auth redirect guards (brief §5.1).
final appRouterProvider = Provider<GoRouter>((ref) {
  final repo = ref.watch(authRepositoryProvider);

  // Subscribe to passwordRecoveryProvider now, before the app processes any
  // incoming route (e.g. a password-reset deep link). It maps Supabase's
  // broadcast onAuthStateChange stream, which never replays past events —
  // if this were first read lazily from inside `redirect` below (triggered
  // by that same stream via GoRouterRefreshStream), the passwordRecovery
  // event would already be gone by the time this subscribes, and the
  // redirect to the reset-password screen would silently never happen.
  ref.listen(passwordRecoveryProvider, (_, _) {});

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: ref.read(lastTabProvider),
    refreshListenable: GoRouterRefreshStream(repo.authStateChanges()),
    redirect: (BuildContext context, GoRouterState state) {
      final bool onboarded = ref.read(onboardingCompleteProvider);
      // Read the session synchronously from Supabase rather than the
      // StreamProvider: when the auth event fires (driving refreshListenable),
      // `currentUser` is already updated, whereas the StreamProvider's cached
      // value may lag by a microtask and leave the user stuck on /auth.
      final bool signedIn = repo.currentUser != null;
      final String location = state.matchedLocation;
      final bool onOnboarding = location == AppRoutes.onboarding;
      final bool onAuthRoute = location == AppRoutes.auth;

      // First-launch: force onboarding until completed.
      if (!onboarded) return onOnboarding ? null : AppRoutes.onboarding;

      // Onboarded but signed out: only the auth route is allowed.
      if (!signedIn) return onAuthRoute ? null : AppRoutes.auth;

      // A password-reset email link grants a temporary session for exactly
      // one purpose — setting a new password — so it overrides the normal
      // signed-in routing below until that's done. See
      // docs/auth-email-links.md.
      final bool inRecovery = ref.read(passwordRecoveryProvider).value ?? false;
      final bool onResetPassword = location == AppRoutes.resetPassword;
      if (inRecovery) return onResetPassword ? null : AppRoutes.resetPassword;

      // Signed in: keep users out of the onboarding/auth routes.
      if (onAuthRoute || onOnboarding) return AppRoutes.home;

      // Remember the active bottom-nav tab so a full app restart (not just
      // backgrounding, which the shell already survives on its own) resumes
      // here instead of always landing back on Home.
      if (kShellTabPaths.contains(location)) {
        unawaited(ref.read(lastTabProvider.notifier).setTab(location));
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        builder: (_, _) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.auth,
        name: 'auth',
        builder: (_, _) => const AuthScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        name: 'reset-password',
        builder: (_, _) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.person}/:id',
        name: 'person',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, GoRouterState state) =>
            PersonProfileScreen(personId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '${AppRoutes.record}/:id',
        name: 'record',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, GoRouterState state) =>
            RecordDetailScreen(recordId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.hints,
        name: 'hints',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const HintsScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        name: 'notifications',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.roleVerificationReview,
        name: 'role-verification-review',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const RoleVerificationReviewScreen(),
      ),
      GoRoute(
        path: AppRoutes.companyRequests,
        name: 'company-requests',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => CompanyRequestsScreen(
          openOpportunityId: state.uri.queryParameters['openId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.submissionReview,
        name: 'submission-review',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => SubmissionReviewScreen(
          openOpportunityId: state.uri.queryParameters['openId'],
        ),
      ),
      GoRoute(
        path: '${AppRoutes.records}/search/:type',
        name: 'records-search',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, GoRouterState state) {
          final String? param = state.pathParameters['type'];
          // "all" => search across every record type (null).
          final RecordType? type = param == 'all'
              ? null
              : RecordType.values.firstWhere(
                  (t) => t.name == param,
                  orElse: () => RecordType.other,
                );
          return HistoricalRecordsSearchScreen(type: type);
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, StatefulNavigationShell shell) =>
            HomeShell(navigationShell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.home,
                name: 'home',
                builder: (_, _) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.tree,
                name: 'tree',
                builder: (_, _) => const TreeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.records,
                name: 'records',
                builder: (_, _) => const RecordsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.collab,
                name: 'collab',
                builder: (_, state) => OpportunitiesScreen(
                  openOpportunityId: state.uri.queryParameters['openId'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.profile,
                name: 'profile',
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
