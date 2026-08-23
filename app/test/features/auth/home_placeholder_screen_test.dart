// app/test/features/auth/home_placeholder_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/auth/home_placeholder_screen.dart';

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

  setUp(() {
    rootBundle.clear();
  });

  testWidgets('renders verified placeholder copy', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/requirement-board', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requirements', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-matches', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requests', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text("You're verified"), findsOneWidget);
    expect(find.text('Dashboard coming soon.'), findsOneWidget);
  });

  testWidgets('tapping the marketplace link navigates to /marketplace', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const Text('marketplace-screen')),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/requirement-board', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requirements', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-matches', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requests', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('marketplace_title_placeholder_link'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('marketplace-screen'), findsOneWidget);
  });

  testWidgets('tapping the my inventory link navigates to /my-inventory', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Text('inventory-screen')),
      GoRoute(path: '/requirement-board', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requirements', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-matches', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requests', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('inventory_title_placeholder_link'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('inventory-screen'), findsOneWidget);
  });

  testWidgets('tapping the requirement board link navigates to /requirement-board', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/requirement-board', builder: (context, state) => const Text('requirement-board-screen')),
      GoRoute(path: '/my-requirements', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-matches', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requests', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('requirement_board_title_placeholder_link'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('requirement-board-screen'), findsOneWidget);
  });

  testWidgets('tapping the my requirements link navigates to /my-requirements', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/requirement-board', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requirements', builder: (context, state) => const Text('my-requirements-screen')),
      GoRoute(path: '/my-matches', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requests', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('my_requirements_title_placeholder_link'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('my-requirements-screen'), findsOneWidget);
  });

  testWidgets('tapping the my matches link navigates to /my-matches', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/requirement-board', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requirements', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-matches', builder: (context, state) => const Text('my-matches-screen')),
      GoRoute(path: '/my-requests', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('matching_my_matches_link'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('my-matches-screen'), findsOneWidget);
  });

  testWidgets('tapping the my requests link navigates to /my-requests', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/requirement-board', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requirements', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-matches', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requests', builder: (context, state) => const Text('my-requests-screen')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('cobroke_request_my_requests_link'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('my-requests-screen'), findsOneWidget);
  });

  testWidgets('tapping the profile icon navigates to /profile', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/requirement-board', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requirements', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-matches', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requests', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/profile', builder: (context, state) => const Text('profile-screen')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();

    expect(find.text('profile-screen'), findsOneWidget);
  });
}
