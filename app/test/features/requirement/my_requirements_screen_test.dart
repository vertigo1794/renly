import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/requirement/models/requirement.dart';
import 'package:renly/features/requirement/my_requirements_screen.dart';
import 'package:renly/features/requirement/requirement_providers.dart';

final _fixtureRequirements = [
  const Requirement(
    requirementId: 'r-1',
    negotiatorId: 'n-1',
    propertyType: 'house',
    transactionType: 'sale',
    state: 'Johor',
    area: 'Iskandar Puteri',
    budgetMin: 500000,
    budgetMax: 700000,
    photoUrls: [],
    status: 'open',
  ),
  const Requirement(
    requirementId: 'r-2',
    negotiatorId: 'n-1',
    propertyType: 'house',
    transactionType: 'sale',
    state: 'Johor',
    area: 'Iskandar Puteri',
    budgetMin: 800000,
    budgetMax: 900000,
    photoUrls: [],
    status: 'fulfilled',
  ),
];

Widget _wrap(GoRouter router) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      myRequirementsProvider.overrideWith((ref, negotiatorId) async => _fixtureRequirements),
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

  testWidgets('Open tab shows only open requirements by default', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequirementsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('RM 500,000 - RM 700,000'), findsOneWidget);
    expect(find.text('RM 800,000 - RM 900,000'), findsNothing);
  });

  testWidgets('switching to Fulfilled tab shows only fulfilled requirements', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequirementsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fulfilled'));
    await tester.pumpAndSettle();

    expect(find.text('RM 800,000 - RM 900,000'), findsOneWidget);
    expect(find.text('RM 500,000 - RM 700,000'), findsNothing);
  });

  testWidgets('tapping Post New Requirement navigates to /post-requirement', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequirementsScreen()),
      GoRoute(path: '/post-requirement', builder: (context, state) => const Text('post-requirement-screen')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Requirement'));
    await tester.pumpAndSettle();

    expect(find.text('post-requirement-screen'), findsOneWidget);
  });
}
