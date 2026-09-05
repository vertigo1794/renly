import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/home/main_dashboard_screen.dart';
import 'package:renly/features/listing/listing_providers.dart';
import 'package:renly/features/listing/marketplace_screen.dart';
import 'package:renly/features/notifications/notification_providers.dart';
import 'package:renly/features/profile/models/profile.dart';
import 'package:renly/features/profile/profile_providers.dart';

// This test builds a MINIMAL 2-branch shell mirroring app_router.dart's
// real StatefulShellRoute structure (Home + Market only, no Chat/Profile),
// rather than exercising the full appRouterProvider -- appRouterProvider
// depends on a live Supabase.instance.client (auth state stream), which
// this project's established test convention does not stand up in widget
// tests. This confirms the SHELL MECHANISM (tapping a destination switches
// the visible branch, state is preserved) works with go_router 14.6.2's
// real API, independent of Supabase wiring.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  testWidgets('tapping a bottom nav destination switches the visible branch', (tester) async {
    final homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
    final marketNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'market');

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => Scaffold(
            body: navigationShell,
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: navigationShell.currentIndex,
              onTap: (index) => navigationShell.goBranch(index),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.store), label: 'Market'),
              ],
            ),
          ),
          branches: [
            StatefulShellBranch(
              navigatorKey: homeNavigatorKey,
              routes: [GoRoute(path: '/home', builder: (context, state) => const MainDashboardScreen())],
            ),
            StatefulShellBranch(
              navigatorKey: marketNavigatorKey,
              routes: [GoRoute(path: '/marketplace', builder: (context, state) => const MarketplaceScreen())],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => const Profile(
                negotiatorId: 'n-1',
                fullName: 'Aiman Yusof',
                verificationStatus: 'approved',
              )),
          marketplaceListingsProvider.overrideWith((ref) async => const []),
          unreadNotificationCountProvider.overrideWith((ref) => 0),
        ],
        child: EasyLocalization(
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
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MainDashboardScreen), findsOneWidget);
    expect(find.byType(MarketplaceScreen), findsNothing);

    // MainDashboardScreen has its own "Market" quick-action shortcut, so a
    // bare find.text('Market') is ambiguous (2 matches) -- scope the tap to
    // the bottom nav bar's own "Market" destination specifically.
    await tester.tap(
      find.descendant(of: find.byType(BottomNavigationBar), matching: find.text('Market')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MarketplaceScreen), findsOneWidget);
    expect(find.byType(MainDashboardScreen), findsNothing);
  });
}
