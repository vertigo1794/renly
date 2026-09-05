// app/test/features/matching/my_matches_screen_test.dart
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
import 'package:renly/features/matching/matching_providers.dart';
import 'package:renly/features/matching/models/match_candidate.dart';
import 'package:renly/features/matching/my_matches_screen.dart';
import 'package:renly/features/requirement/models/requirement.dart';

final _myListing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'My Listing',
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

const _theirRequirement = Requirement(
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

final _theirListing = Listing(
  listingId: 'l-2',
  negotiatorId: 'n-3',
  title: 'Their Listing',
  description: 'd',
  propertyType: 'house',
  transactionType: 'sale',
  state: 'Johor',
  area: 'Iskandar Puteri',
  price: 800000,
  photoUrls: [],
  status: 'active',
  createdAt: DateTime(2024, 1, 1),
);

const _myRequirement = Requirement(
  requirementId: 'r-2',
  negotiatorId: 'n-1',
  propertyType: 'house',
  transactionType: 'sale',
  state: 'Johor',
  area: 'Iskandar Puteri',
  budgetMin: 700000,
  budgetMax: 900000,
  photoUrls: [],
  status: 'open',
);

const _owner = ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345');

final _fixtureMatches = [
  MatchCandidate(
    matchId: 'm-1',
    score: 90,
    listing: _myListing,
    requirement: _theirRequirement,
    listingOwner: _owner,
    requirementOwner: _owner,
  ),
  MatchCandidate(
    matchId: 'm-2',
    score: 80,
    listing: _theirListing,
    requirement: _myRequirement,
    listingOwner: _owner,
    requirementOwner: _owner,
  ),
];

Widget _wrap(GoRouter router) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      myMatchesProvider.overrideWith((ref) async => _fixtureMatches),
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

  testWidgets('shows the other side for both my-listing and my-requirement matches', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyMatchesScreen()),
      GoRoute(path: '/requirement-board/:requirementId', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/property/:listingId', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('RM 300,000 - RM 500,000'), findsOneWidget);
    expect(find.text('RM 800,000'), findsOneWidget);
  });

  testWidgets('tapping a my-listing match navigates to the requirement route', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyMatchesScreen()),
      GoRoute(
        path: '/requirement-board/:requirementId',
        builder: (context, state) => Text('req-detail-${state.pathParameters['requirementId']}'),
      ),
      GoRoute(path: '/property/:listingId', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('90/100'));
    await tester.pumpAndSettle();

    expect(find.text('req-detail-r-1'), findsOneWidget);
  });

  testWidgets('tapping a my-requirement match navigates to the property route', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyMatchesScreen()),
      GoRoute(path: '/requirement-board/:requirementId', builder: (context, state) => const Placeholder()),
      GoRoute(
        path: '/property/:listingId',
        builder: (context, state) => Text('property-detail-${state.pathParameters['listingId']}'),
      ),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('80/100'));
    await tester.pumpAndSettle();

    expect(find.text('property-detail-l-2'), findsOneWidget);
  });
}
