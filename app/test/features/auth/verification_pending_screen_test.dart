import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/core/widgets/brutalist_button.dart';
import 'package:renly/features/auth/verification_pending_screen.dart';

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

  // Same rootBundle-cache-vs-FakeAsync-zone issue documented across every
  // other auth screen test in this project -- clear before every test.
  setUp(() => rootBundle.clear());

  testWidgets('renders localized verification pending copy and status badge', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const VerificationPendingScreen()),
      GoRoute(path: '/home', builder: (context, state) => const Placeholder()),
    ]);

    // pumpAndSettle() would hang forever here: the hourglass's
    // AnimationController repeats infinitely (real motion, not a
    // one-shot), so Flutter never sees "no more frames scheduled". A
    // couple of fixed pumps is enough to let go_router build its first
    // real route and settle the animation into steady state.
    await tester.pumpWidget(_wrap(router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Your Account is Being Verified'), findsOneWidget);
    expect(
      find.text('The REN verification process takes 24-48 hours. We will notify you as soon as your profile is approved.'),
      findsOneWidget,
    );
    expect(find.text('IN PROGRESS'), findsOneWidget);
    expect(find.text('renly'), findsOneWidget);
  });

  testWidgets('tapping Back to Home navigates to /home', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const VerificationPendingScreen()),
      GoRoute(path: '/home', builder: (context, state) => const Text('home-screen')),
    ]);

    // Same reasoning as above: this screen's own infinite animation means
    // pumpAndSettle() never returns, so every pump here is a fixed one.
    await tester.pumpWidget(_wrap(router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(BrutalistButton, 'Back to Home'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('home-screen'), findsOneWidget);
  });
}
