// app/test/features/requirement/requirement_board_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/core/widgets/negotiator_avatar.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/requirement/models/requirement.dart';
import 'package:renly/features/requirement/requirement_board_screen.dart';
import 'package:renly/features/requirement/requirement_providers.dart';

final _fixtureRequirements = [
  const Requirement(
    requirementId: 'r-1',
    negotiatorId: 'n-1',
    propertyType: 'apartment',
    transactionType: 'sale',
    state: 'Selangor',
    area: 'Petaling Jaya',
    budgetMin: 300000,
    budgetMax: 500000,
    bedrooms: 3,
    photoUrls: [],
    status: 'open',
  ),
  const Requirement(
    requirementId: 'r-2',
    negotiatorId: 'n-2',
    propertyType: 'apartment',
    transactionType: 'rent',
    state: 'W.P. Kuala Lumpur',
    area: 'Bukit Bintang',
    budgetMin: 2000,
    budgetMax: 3500,
    bedrooms: 1,
    photoUrls: [],
    status: 'open',
  ),
];

const _fixtureOwner = ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345');

Widget _wrap(GoRouter router, {List<Requirement>? requirements}) {
  return ProviderScope(
    overrides: [
      boardRequirementsProvider.overrideWith((ref) async => requirements ?? _fixtureRequirements),
      requirementOwnerProvider.overrideWith((ref, negotiatorId) async => _fixtureOwner),
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

  testWidgets('renders formatted budget range, criteria, area, and owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementBoardScreen()),
      GoRoute(path: '/requirement-board/:requirementId', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('RM 300,000 - RM 500,000'), findsOneWidget);
    expect(find.text('RM 2,000 - RM 3,500 /mo'), findsOneWidget);
    expect(find.text('Apartment · Sale'), findsOneWidget);
    expect(find.text('Apartment · Rent'), findsOneWidget);
    expect(find.text('Petaling Jaya'), findsOneWidget);
    expect(find.text('Bukit Bintang'), findsOneWidget);
    expect(find.text('Aiman Yusof (REN: 12345)'), findsNWidgets(2));
  });

  testWidgets('tapping a requirement card navigates to its detail route', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementBoardScreen()),
      GoRoute(
        path: '/requirement-board/:requirementId',
        builder: (context, state) => Text('detail-${state.pathParameters['requirementId']}'),
      ),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RM 300,000 - RM 500,000'));
    await tester.pumpAndSettle();

    expect(find.text('detail-r-1'), findsOneWidget);
  });

  testWidgets('renders empty state when no requirements', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementBoardScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, requirements: []));
    await tester.pumpAndSettle();

    expect(find.text('No requirements yet'), findsOneWidget);
  });

  testWidgets('renders a NegotiatorAvatar for each requirement card owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementBoardScreen()),
      GoRoute(path: '/requirement-board/:requirementId', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byType(NegotiatorAvatar), findsNWidgets(2));
  });
}
