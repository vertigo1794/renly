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

  testWidgets('renders the shared header (R monogram + wordmark + Skip)', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/', builder: (context, state) => const Placeholder()),
    ], initialLocation: '/onboarding');

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('R'), findsOneWidget);
    expect(find.text('renly'), findsOneWidget);
    expect(find.text('SKIP'), findsOneWidget);
  });

  testWidgets('renders the first slide badge, title, and body', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/', builder: (context, state) => const Placeholder()),
    ], initialLocation: '/onboarding');

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('CO-BROKE NETWORK'), findsOneWidget);
    expect(find.text('Cross-Agency Collaboration'), findsOneWidget);
    expect(
      find.text('Break down agency barriers. Share listings and co-broke with certified agents across Malaysia seamlessly.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(BrutalistButton, 'Next'), findsOneWidget);
  });

  testWidgets('slide 2 has no badge pill (no badgeKey provided yet)', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/', builder: (context, state) => const Placeholder()),
    ], initialLocation: '/onboarding');

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BrutalistButton, 'Next'));
    await tester.pumpAndSettle();

    expect(find.text('Smart Listing Matching'), findsOneWidget);
    expect(find.text('CO-BROKE NETWORK'), findsNothing);
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

  testWidgets('tapping Next on a non-last slide advances to the next slide', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/', builder: (context, state) => const Placeholder()),
    ], initialLocation: '/onboarding');

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    expect(find.text('Cross-Agency Collaboration'), findsOneWidget);

    await tester.tap(find.widgetWithText(BrutalistButton, 'Next'));
    await tester.pumpAndSettle();

    expect(find.text('Smart Listing Matching'), findsOneWidget);
    expect(find.text('Cross-Agency Collaboration'), findsNothing);
  });

  testWidgets('the last slide shows Get Started (not Next) with a bold "REN Verified"', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/', builder: (context, state) => const Placeholder()),
    ], initialLocation: '/onboarding');

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    // Slides 1 -> 2 -> 3 via Next.
    await tester.tap(find.widgetWithText(BrutalistButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BrutalistButton, 'Next'));
    await tester.pumpAndSettle();

    expect(find.text('Transparent & Verified'), findsOneWidget);
    expect(find.widgetWithText(BrutalistButton, 'Get Started'), findsOneWidget);
    expect(find.widgetWithText(BrutalistButton, 'Next'), findsNothing);

    // The body is a single RichText with "REN Verified" as its own bold
    // span -- not plain text -- matching Stitch's own emphasis on it.
    final allSpans = <TextSpan>[];
    void collect(InlineSpan? span) {
      if (span is TextSpan) {
        allSpans.add(span);
        span.children?.forEach(collect);
      }
    }

    for (final element in find.byType(RichText).evaluate()) {
      collect((element.widget as RichText).text);
    }
    final boldSpan = allSpans.where((s) => s.text == 'REN Verified').firstOrNull;
    expect(boldSpan, isNotNull, reason: 'spans found: ${allSpans.map((s) => s.text).toList()}');
    expect(boldSpan!.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('tapping Get Started on the last slide navigates to /', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/', builder: (context, state) => const Text('auth-selection')),
    ], initialLocation: '/onboarding');

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    // Advance through all 3 slides before checking the final action.
    await tester.tap(find.widgetWithText(BrutalistButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BrutalistButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BrutalistButton, 'Get Started'));
    await tester.pumpAndSettle();

    expect(find.text('auth-selection'), findsOneWidget);
  });
}
