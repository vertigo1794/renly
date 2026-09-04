// app/test/features/auth/splash_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/auth/splash_screen.dart';

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

  testWidgets('renders the wordmark and tagline immediately', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(duration: Duration(milliseconds: 10)),
      ),
      GoRoute(path: '/', builder: (context, state) => const Placeholder()),
    ], initialLocation: '/splash');

    await tester.pumpWidget(_wrap(router));
    await tester.pump();
    await tester.pump();

    expect(find.text('renly'), findsOneWidget);
    expect(find.text('PROPERTY COLLABORATION PLATFORM'), findsOneWidget);

    // Flush the pending navigation Timer before the test ends -- flutter_test
    // asserts no timers are left pending at teardown, regardless of whether
    // they'd fire harmlessly.
    await tester.pumpAndSettle();
  });

  testWidgets('navigates to / once the duration elapses', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(duration: Duration(milliseconds: 10)),
      ),
      GoRoute(path: '/', builder: (context, state) => const Text('auth-selection')),
    ], initialLocation: '/splash');

    await tester.pumpWidget(_wrap(router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    expect(find.text('auth-selection'), findsOneWidget);
  });
}
