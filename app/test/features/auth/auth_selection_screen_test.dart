// app/test/features/auth/auth_selection_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/core/widgets/brutalist_button.dart';
import 'package:renly/features/auth/auth_selection_screen.dart';

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

  // `rootBundle` (a `CachingAssetBundle`) caches loaded asset Futures for the
  // lifetime of the test process, but `flutter_test` runs each `testWidgets`
  // body inside its own fresh FakeAsync zone. A Future that was completed
  // inside a previous test's zone never delivers its result to a new
  // listener registered from a later test's zone, so any subsequent
  // `EasyLocalization` tree in this file hangs forever waiting on the cached
  // (already "dead") translations-loading Future instead of the buttons'
  // translated text ever rendering. Clearing the bundle cache before each
  // test forces a fresh load tied to that test's own zone.
  setUp(() {
    rootBundle.clear();
  });

  testWidgets('renders tagline and both action buttons', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthSelectionScreen()),
      GoRoute(path: '/register/personal', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/login', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Collaborate smarter, close faster.'), findsOneWidget);
    expect(find.widgetWithText(BrutalistButton, 'Create account'), findsOneWidget);
    expect(find.widgetWithText(BrutalistButton, 'Log In'), findsOneWidget);
  });

  testWidgets('tapping Create account navigates to /register/personal', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthSelectionScreen()),
      GoRoute(path: '/register/personal', builder: (context, state) => const Text('personal-step')),
      GoRoute(path: '/login', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BrutalistButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('personal-step'), findsOneWidget);
  });

  testWidgets('tapping Log In navigates to /login', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthSelectionScreen()),
      GoRoute(path: '/register/personal', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/login', builder: (context, state) => const Text('login-screen')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BrutalistButton, 'Log In'));
    await tester.pumpAndSettle();

    expect(find.text('login-screen'), findsOneWidget);
  });
}
