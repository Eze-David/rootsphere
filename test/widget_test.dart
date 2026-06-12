import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootsphere/app.dart';
import 'package:rootsphere/core/storage/preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpApp(WidgetTester tester, SharedPreferences prefs) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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

    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Rootsphere'), findsOneWidget);
  });

  testWidgets('Returning (onboarded) users see the auth screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_complete': true,
    });
    final prefs = await SharedPreferences.getInstance();

    await _pumpApp(tester, prefs);

    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('or continue with'), findsOneWidget);
  });
}
