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

  testWidgets('renders the R-star badge image and wordmark text on its first frame', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const Placeholder()),
    ], initialLocation: '/splash');

    // MaterialApp.router/GoRouter needs one pump beyond pumpWidget() itself
    // before SplashScreen's first frame actually builds (confirmed
    // empirically: pumpWidget() alone still shows the Router's own
    // placeholder, not SplashScreen).
    await tester.pumpWidget(_wrap(router));
    await tester.pump();

    // The badge and wordmark are both present from the first frame -- only
    // their AnimatedScale/AnimatedOpacity values change once the ~700ms
    // reveal fires, not their presence in the tree. The splash is
    // deliberately plain below the logo now -- no tagline text at all.
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, 'assets/illustrations/renly_r_star_badge.png');
    expect(find.text('renly'), findsOneWidget);

    // Flush the 3.5s delay and the resulting navigation before the test
    // ends. pumpAndSettle() alone won't do it: nothing rebuilds while the
    // Future.delayed is pending, so it sees no scheduled frame and
    // considers itself "settled" well before the fake clock actually
    // reaches 3.5s -- pump() past that mark explicitly first.
    await tester.pump(const Duration(milliseconds: 3500));
    await tester.pumpAndSettle();
  });

  testWidgets('navigates to /onboarding after its own 3.5s on-screen delay', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const Text('onboarding')),
    ], initialLocation: '/splash');

    await tester.pumpWidget(_wrap(router));
    await tester.pump();
    expect(find.text('onboarding'), findsNothing);

    // Same reasoning as above: pumpAndSettle() alone never advances the
    // fake clock far enough to fire the 3.5s Future.delayed.
    await tester.pump(const Duration(milliseconds: 3500));
    await tester.pumpAndSettle();

    expect(find.text('onboarding'), findsOneWidget);
  });
}
