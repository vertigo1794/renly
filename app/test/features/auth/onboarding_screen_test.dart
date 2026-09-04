// app/test/features/auth/onboarding_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/core/widgets/brutalist_button.dart';
import 'package:renly/features/auth/onboarding_screen.dart';

Widget _wrap(GoRouter router) {
  return EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('ms')],
    path: 'assets/translations',
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) => MaterialApp.router(
        theme: AppTheme.light,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        routerConfig: router,
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  // Same rootBundle-cache-vs-FakeAsync-zone issue documented in
  // auth_selection_screen_test.dart -- clear before every test.
  setUp(() {
    rootBundle.clear();
  });

  testWidgets('renders the first slide title and body', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/', builder: (context, state) => const Placeholder()),
    ], initialLocation: '/onboarding');

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Cross-Agency Collaboration'), findsOneWidget);
    expect(
      find.text(
        "Break down agency barriers. Share listings and find clients with ease on Malaysia's premier agent network.",
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(BrutalistButton, 'Next'), findsOneWidget);
  });

  testWidgets('tapping Skip navigates to /', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/', builder: (context, state) => const Text('auth-selection')),
    ], initialLocation: '/onboarding');

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SKIP'));
    await tester.pumpAndSettle();

    expect(find.text('auth-selection'), findsOneWidget);
  });

  testWidgets('tapping Next on the last (only) slide navigates to /', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/', builder: (context, state) => const Text('auth-selection')),
    ], initialLocation: '/onboarding');

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BrutalistButton, 'Next'));
    await tester.pumpAndSettle();

    expect(find.text('auth-selection'), findsOneWidget);
  });
}
