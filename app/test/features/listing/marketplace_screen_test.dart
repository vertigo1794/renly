import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/listing/listing_providers.dart';
import 'package:renly/features/listing/marketplace_screen.dart';
import 'package:renly/features/listing/models/listing.dart';

final _fixtureListings = [
  Listing(
    listingId: 'l-1',
    negotiatorId: 'n-1',
    title: 'The Vertex Residency',
    description: 'A modern apartment.',
    propertyType: 'apartment',
    transactionType: 'sale',
    state: 'Selangor',
    area: 'Petaling Jaya',
    price: 1250000,
    bedrooms: 3,
    bathrooms: 2,
    photoUrls: [],
    status: 'active',
    createdAt: DateTime(2024, 1, 1),
  ),
  Listing(
    listingId: 'l-2',
    negotiatorId: 'n-2',
    title: 'City Loft',
    description: 'Rental loft.',
    propertyType: 'apartment',
    transactionType: 'rent',
    state: 'W.P. Kuala Lumpur',
    area: 'Bukit Bintang',
    price: 3500,
    bedrooms: 1,
    bathrooms: 1,
    photoUrls: [],
    status: 'active',
    createdAt: DateTime(2024, 1, 1),
  ),
];

Widget _wrap(GoRouter router, {List<Listing>? listings}) {
  return ProviderScope(
    overrides: [
      marketplaceListingsProvider.overrideWith((ref) async => listings ?? _fixtureListings),
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

  testWidgets('renders active listings with formatted price and area', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MarketplaceScreen()),
      GoRoute(path: '/property/:listingId', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('RM 1,250,000'), findsOneWidget);
    expect(find.text('RM 3,500 /mo'), findsOneWidget);
    expect(find.text('Petaling Jaya'), findsOneWidget);
    expect(find.text('Bukit Bintang'), findsOneWidget);
  });

  testWidgets('tapping a listing card navigates to its property detail route', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MarketplaceScreen()),
      GoRoute(
        path: '/property/:listingId',
        builder: (context, state) => Text('detail-${state.pathParameters['listingId']}'),
      ),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The Vertex Residency'));
    await tester.pumpAndSettle();

    expect(find.text('detail-l-1'), findsOneWidget);
  });

  testWidgets('renders empty state when no listings', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MarketplaceScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, listings: []));
    await tester.pumpAndSettle();

    expect(find.text('No listings yet'), findsOneWidget);
  });
}
