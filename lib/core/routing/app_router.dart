import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/auth_screen.dart';
import '../../features/onboarding/presentation/providers/onboarding_provider.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/tree/presentation/screens/person_profile_screen.dart';
import '../../features/tree/presentation/screens/tree_screen.dart';
import '../../shared/widgets/home_shell.dart';
import '../../shared/widgets/placeholder_screen.dart';
import 'app_routes.dart';
import 'go_router_refresh_stream.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Application router with auth redirect guards (brief §5.1).
final appRouterProvider = Provider<GoRouter>((ref) {
  final repo = ref.watch(authRepositoryProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.home,
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

      // Signed in: keep users out of the onboarding/auth routes.
      if (onAuthRoute || onOnboarding) return AppRoutes.home;
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
        path: '${AppRoutes.person}/:id',
        name: 'person',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, GoRouterState state) =>
            PersonProfileScreen(personId: state.pathParameters['id']!),
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
                builder: (_, _) => const PlaceholderScreen(
                  title: 'Home',
                  icon: Icons.home_outlined,
                  phase: 'Phase 2',
                ),
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
                builder: (_, _) => const PlaceholderScreen(
                  title: 'Records',
                  icon: Icons.description_outlined,
                  phase: 'Phase 3',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.collab,
                name: 'collab',
                builder: (_, _) => const PlaceholderScreen(
                  title: 'Opportunities',
                  icon: Icons.groups_outlined,
                  phase: 'Phase 5',
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
