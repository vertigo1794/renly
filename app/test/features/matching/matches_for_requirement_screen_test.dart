import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/matching/matches_for_requirement_screen.dart';
import 'package:renly/features/matching/matching_providers.dart';
import 'package:renly/features/matching/models/match_candidate.dart';
import 'package:renly/features/requirement/models/requirement.dart';

final _fixtureListing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'The Vertex Residency',
  description: 'd',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  price: 400000,
  photoUrls: [],
  status: 'active',
  createdAt: DateTime(2024, 1, 1),
);

const _fixtureRequirement = Requirement(
  requirementId: 'r-1',
  negotiatorId: 'n-2',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  budgetMin: 300000,
  budgetMax: 500000,
  photoUrls: [],
  status: 'open',
);

const _fixtureOwner = ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345');

final _fixtureMatches = [
  MatchCandidate(
    matchId: 'm-1',
    score: 90,
    listing: _fixtureListing,
    requirement: _fixtureRequirement,
    listingOwner: _fixtureOwner,
    requirementOwner: _fixtureOwner,
  ),
];

Widget _wrap(GoRouter router, {List<MatchCandidate>? matches}) {
  return ProviderScope(
    overrides: [
      matchesForRequirementProvider.overrideWith((ref, requirementId) async => matches ?? _fixtureMatches),
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

  testWidgets('renders score, price, area, and owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MatchesForRequirementScreen(requirementId: 'r-1')),
      GoRoute(path: '/property/:listingId', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('90/100'), findsOneWidget);
    expect(find.text('RM 400,000'), findsOneWidget);
    expect(find.text('Petaling Jaya'), findsOneWidget);
    expect(find.text('Aiman Yusof (REN: 12345)'), findsOneWidget);
  });

  testWidgets('tapping a match navigates to the property detail route', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MatchesForRequirementScreen(requirementId: 'r-1')),
      GoRoute(
        path: '/property/:listingId',
        builder: (context, state) => Text('detail-${state.pathParameters['listingId']}'),
      ),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('90/100'));
    await tester.pumpAndSettle();

    expect(find.text('detail-l-1'), findsOneWidget);
  });

  testWidgets('renders empty state when no matches', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MatchesForRequirementScreen(requirementId: 'r-1')),
    ]);

    await tester.pumpWidget(_wrap(router, matches: []));
    await tester.pumpAndSettle();

    expect(find.text('No matches yet'), findsOneWidget);
  });
}
