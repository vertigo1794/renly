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

  testWidgets('renders the wordmark image and tagline on its first frame', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const Placeholder()),
    ], initialLocation: '/splash');

    // No duration to override any more. MaterialApp.router/GoRouter needs
    // one pump beyond pumpWidget() itself before SplashScreen's first
    // frame actually builds (confirmed empirically: pumpWidget() alone
    // still shows the Router's own placeholder, not SplashScreen) -- the
    // post-frame callback that removes the native splash and navigates
    // away fires at the end of THAT frame, but go_router's own route
    // change doesn't visually land until a further pump, leaving this one
    // pump as a real, if narrow, window onto SplashScreen's own content.
    await tester.pumpWidget(_wrap(router));
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, 'assets/illustrations/renly_wordmark.png');
    expect(find.text('PROPERTY COLLABORATION PLATFORM'), findsOneWidget);

    // Flush the 800ms delay and the resulting navigation before the test
    // ends. pumpAndSettle() alone won't do it: nothing rebuilds while the
    // Future.delayed is pending, so it sees no scheduled frame and
    // considers itself "settled" well before the fake clock actually
    // reaches 800ms -- pump() past that mark explicitly first.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
  });

  testWidgets('navigates to /onboarding after the 800ms native-splash delay', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const Text('onboarding')),
    ], initialLocation: '/splash');

    await tester.pumpWidget(_wrap(router));
    await tester.pump();
    expect(find.text('onboarding'), findsNothing);

    // Same reasoning as above: pumpAndSettle() alone never advances the
    // fake clock far enough to fire the 800ms Future.delayed.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(find.text('onboarding'), findsOneWidget);
  });
}
