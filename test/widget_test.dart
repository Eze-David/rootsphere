import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:rootsphere/app.dart';
import 'package:rootsphere/core/storage/preferences_provider.dart';
import 'package:rootsphere/features/auth/domain/entities/app_user.dart';
import 'package:rootsphere/features/auth/domain/repositories/auth_repository.dart';
import 'package:rootsphere/features/auth/presentation/providers/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _signedInUser = AppUser(id: 'u1', email: 'test@example.com');

/// Always-signed-in [AuthRepository] double, for exercising screens/routes
/// that require a session without touching Supabase.
class _FakeSignedInAuthRepository implements AuthRepository {
  @override
  AppUser? get currentUser => _signedInUser;

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(_signedInUser);

  @override
  Stream<bool> passwordRecoveryEvents() => Stream.value(false);

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> signUpWithEmail({
    required String fullName,
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> signInWithGoogle() => throw UnimplementedError();

  @override
  Future<void> signInWithApple() => throw UnimplementedError();

  @override
  Future<void> sendPasswordReset(String email) => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<void> updatePassword(String newPassword) => throw UnimplementedError();

  @override
  Future<void> deleteAccount() => throw UnimplementedError();

  @override
  Future<void> resendEmailConfirmation(String email) =>
      throw UnimplementedError();
}

Future<void> _pumpApp(
  WidgetTester tester,
  SharedPreferences prefs, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...overrides,
      ],
      child: const RootsphereApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('First launch shows the onboarding screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await _pumpApp(tester, prefs);

    // New marketing landing page: hero with logo/title and CTAs.
    expect(find.text('Rootsphere'), findsOneWidget);
    expect(find.text('Get started'), findsWidgets);
    expect(find.text('Sign in'), findsWidgets);
  });

  testWidgets(
    'Returning (onboarded) signed-out users see the landing page again',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'onboarding_complete': true,
      });
      final prefs = await SharedPreferences.getInstance();

      await _pumpApp(tester, prefs);

      // Signed-out users always land on the marketing page (e.g. right
      // after logout), not straight on the auth form.
      expect(find.text('Rootsphere'), findsOneWidget);
      expect(find.text('Get started'), findsWidgets);
    },
  );

  testWidgets(
    'Signed-in users resume on the last bottom-nav tab they were on',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'onboarding_complete': true,
        'last_tab_path': '/records',
      });
      final prefs = await SharedPreferences.getInstance();

      await _pumpApp(
        tester,
        prefs,
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeSignedInAuthRepository(),
          ),
        ],
      );

      // Records screen's static hero copy, not the Home dashboard's.
      expect(find.text('Your records'), findsOneWidget);
      expect(find.text('RECENT ACTIVITY'), findsNothing);
    },
  );
}
