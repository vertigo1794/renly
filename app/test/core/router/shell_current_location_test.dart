import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/router/app_router.dart';
import 'package:renly/features/notifications/foreground_suppression.dart';

// Regression coverage for the Task 8 shell/observer interaction.
//
// StatefulShellRoute.indexedStack has no name and no path of its own, so
// go_router builds its page with `name: null`. CurrentLocationObserver._record
// deliberately early-returns on a null name, which meant that popping back
// onto the shell from a root-level pushed route (e.g. '/messages/req-1') left
// currentLocation stuck on the POPPED route -- and
// shouldSuppressForegroundBanner then wrongly suppressed a chat push banner
// while the user was actually sitting on a bottom-nav tab.
//
// Like main_shell_test.dart, this builds a MINIMAL replica of app_router.dart's
// real structure (the REAL MainShell widget + the real 4-branch
// StatefulShellRoute shape + a flat '/messages/:requestId' route outside the
// shell) with placeholder branch screens, because appRouterProvider itself
// needs a live Supabase client.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  Widget placeholder(String label) => Scaffold(body: Center(child: Text(label)));

  ({GoRouter router, CurrentLocationObserver observer}) buildRouter() {
    final observer = CurrentLocationObserver();
    final router = GoRouter(
      initialLocation: '/home',
      observers: [observer],
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              MainShell(navigationShell: navigationShell, locationObserver: observer),
          branches: [
            StatefulShellBranch(
              routes: [GoRoute(path: '/home', builder: (c, s) => placeholder('HomeBranch'))],
            ),
            StatefulShellBranch(
              routes: [GoRoute(path: '/marketplace', builder: (c, s) => placeholder('MarketBranch'))],
            ),
            StatefulShellBranch(
              routes: [GoRoute(path: '/chat', builder: (c, s) => placeholder('ChatBranch'))],
            ),
            StatefulShellBranch(
              routes: [GoRoute(path: '/profile', builder: (c, s) => placeholder('ProfileBranch'))],
            ),
          ],
        ),
        GoRoute(
          path: '/messages/:requestId',
          builder: (c, s) => placeholder('Chat ${s.pathParameters['requestId']}'),
        ),
        GoRoute(path: '/notifications', builder: (c, s) => placeholder('Notifications')),
      ],
    );
    return (router: router, observer: observer);
  }

  Future<void> pumpApp(WidgetTester tester, GoRouter router) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ms')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        child: Builder(
          builder: (context) => MaterialApp.router(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the shell reports its active branch as the current location on first display',
      (tester) async {
    final (:router, :observer) = buildRouter();
    await pumpApp(tester, router);

    expect(observer.currentLocation.value, '/home');
  });

  testWidgets('popping back onto the shell restores the active branch, not the popped route',
      (tester) async {
    final (:router, :observer) = buildRouter();
    await pumpApp(tester, router);

    // Existing (already-working) behaviour: a flat route pushed OUTSIDE the
    // shell, on the root navigator, is recorded with its parameter resolved.
    router.push('/messages/req-1');
    await tester.pumpAndSettle();
    expect(observer.currentLocation.value, '/messages/req-1');

    // The regression: didPop hands the observer the shell's own unnamed page
    // as previousRoute. Pre-fix this was ignored and currentLocation stayed
    // '/messages/req-1' while the user was looking at the Home tab.
    router.pop();
    await tester.pumpAndSettle();
    expect(observer.currentLocation.value, '/home');

    // ...and therefore a foreground push for that same chat is NOT suppressed
    // any more, which is the whole reason currentLocation exists.
    expect(
      shouldSuppressForegroundBanner(
        category: 'message',
        currentRouteLocation: observer.currentLocation.value,
        data: const {'request_id': 'req-1'},
      ),
      isFalse,
    );
  });

  testWidgets('popping back from /notifications restores the active branch', (tester) async {
    // '/notifications' is the OTHER flat route outside the shell (the bell on
    // MainDashboardScreen pushes it), so it hits the same didPop-onto-an-
    // unnamed-shell-page path as '/messages/:id' above. Covered explicitly
    // because it is the one shell-adjacent route the Notification Center
    // milestone added, and a regression here would silently mis-suppress
    // foreground push banners the same way.
    final (:router, :observer) = buildRouter();
    await pumpApp(tester, router);

    router.push('/notifications');
    await tester.pumpAndSettle();
    expect(observer.currentLocation.value, '/notifications');

    router.pop();
    await tester.pumpAndSettle();
    expect(observer.currentLocation.value, '/home');

    expect(
      shouldSuppressForegroundBanner(
        category: 'message',
        currentRouteLocation: observer.currentLocation.value,
        data: const {'request_id': 'req-1'},
      ),
      isFalse,
    );
  });

  testWidgets('switching bottom-nav branches updates the current location for all 4 branches',
      (tester) async {
    final (:router, :observer) = buildRouter();
    await pumpApp(tester, router);

    final shell = tester.widget<MainShell>(find.byType(MainShell)).navigationShell;

    for (final (index, expected) in const [
      (1, '/marketplace'),
      (2, '/chat'),
      (3, '/profile'),
      (0, '/home'),
    ]) {
      shell.goBranch(index);
      await tester.pumpAndSettle();
      expect(observer.currentLocation.value, expected, reason: 'branch $index');
    }
  });

  testWidgets('popping back restores whichever branch is active, not just Home', (tester) async {
    final (:router, :observer) = buildRouter();
    await pumpApp(tester, router);

    tester.widget<MainShell>(find.byType(MainShell)).navigationShell.goBranch(2);
    await tester.pumpAndSettle();
    expect(observer.currentLocation.value, '/chat');

    router.push('/messages/req-9');
    await tester.pumpAndSettle();
    expect(observer.currentLocation.value, '/messages/req-9');

    router.pop();
    await tester.pumpAndSettle();
    expect(observer.currentLocation.value, '/chat');
  });

  testWidgets('a rebuild while a route sits on top of the shell does not clobber that route',
      (tester) async {
    final (:router, :observer) = buildRouter();
    await pumpApp(tester, router);

    router.push('/messages/req-2');
    await tester.pumpAndSettle();
    expect(observer.currentLocation.value, '/messages/req-2');

    // The shell stays mounted (and rebuildable) underneath the pushed route.
    tester.element(find.byType(MainShell, skipOffstage: false)).markNeedsBuild();
    await tester.pumpAndSettle();
    expect(observer.currentLocation.value, '/messages/req-2');
  });
}
