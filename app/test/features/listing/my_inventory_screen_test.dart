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
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/my_inventory_screen.dart';

final _fixtureListings = [
  const Listing(
    listingId: 'l-1',
    negotiatorId: 'n-1',
    title: 'Active One',
    description: 'd',
    propertyType: 'house',
    transactionType: 'sale',
    state: 'Johor',
    area: 'Iskandar Puteri',
    price: 800000,
    photoUrls: [],
    status: 'active',
  ),
  const Listing(
    listingId: 'l-2',
    negotiatorId: 'n-1',
    title: 'Sold One',
    description: 'd',
    propertyType: 'house',
    transactionType: 'sale',
    state: 'Johor',
    area: 'Iskandar Puteri',
    price: 900000,
    photoUrls: [],
    status: 'sold',
  ),
];

Widget _wrap(GoRouter router) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      myListingsProvider.overrideWith((ref, negotiatorId) async => _fixtureListings),
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

  testWidgets('Active tab shows only active listings by default', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyInventoryScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Active One'), findsOneWidget);
    expect(find.text('Sold One'), findsNothing);
  });

  testWidgets('switching to Sold tab shows only sold listings', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyInventoryScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sold'));
    await tester.pumpAndSettle();

    expect(find.text('Sold One'), findsOneWidget);
    expect(find.text('Active One'), findsNothing);
  });

  testWidgets('tapping Post New Listing navigates to /post-listing', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyInventoryScreen()),
      GoRoute(path: '/post-listing', builder: (context, state) => const Text('post-listing-screen')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Listing'));
    await tester.pumpAndSettle();

    expect(find.text('post-listing-screen'), findsOneWidget);
  });
}
