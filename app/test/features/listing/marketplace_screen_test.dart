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
import 'package:renly/features/listing/listing_providers.dart';
import 'package:renly/features/listing/marketplace_screen.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_owner.dart';

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

Widget _wrap(GoRouter router, {List<Listing>? listings, List<Override> extraOverrides = const []}) {
  return ProviderScope(
    overrides: [
      marketplaceListingsProvider.overrideWith((ref) async => listings ?? _fixtureListings),
      ...extraOverrides,
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
    // The default test surface (800x600) is too short to mount every card
    // in the restyled premium feed (~400dp tall each) -- ListView virtualizes
    // via the sliver machinery regardless of the plain-list vs .builder
    // delegate, so an off-screen card's Elements genuinely never mount and
    // find.byType/find.text can't see them. Widen the surface so both
    // fixture cards are within the mount+cache extent.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MarketplaceScreen()),
      GoRoute(path: '/property/:listingId', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('1,250,000'), findsOneWidget);
    expect(find.text('3,500 /mo'), findsOneWidget);
    expect(find.textContaining('Petaling Jaya'), findsOneWidget);
    expect(find.textContaining('Bukit Bintang'), findsOneWidget);
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

  testWidgets('shows a NegotiatorAvatar for the listing owner', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MarketplaceScreen()),
      GoRoute(path: '/property/:listingId', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      extraOverrides: [
        listingOwnerProvider.overrideWith(
          (ref, negotiatorId) async => const ListingOwner(fullName: 'Owner', renNumber: '12345', isOnline: true),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.byType(NegotiatorAvatar), findsWidgets);
  });

  // Regression for the Marketplace presence-staleness gap: this screen is a
  // StatefulShellRoute.indexedStack branch that never disposes, so each
  // row's own .autoDispose listingOwnerProvider instance stays subscribed
  // for the whole session and never refetches on its own. Confirms
  // pull-to-refresh (already this screen's real recovery affordance for
  // the listings themselves) also invalidates listingOwnerProvider, so a
  // negotiator's real current online status is reachable without an app
  // restart.
  testWidgets('pull-to-refresh picks up a fresh online status for the listing owner', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var fetchCount = 0;
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MarketplaceScreen()),
      GoRoute(path: '/property/:listingId', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      extraOverrides: [
        listingOwnerProvider.overrideWith((ref, negotiatorId) async {
          fetchCount++;
          return ListingOwner(fullName: 'Owner', renNumber: '12345', isOnline: fetchCount > 1);
        }),
      ],
    ));
    await tester.pumpAndSettle();

    expect(tester.widget<NegotiatorAvatar>(find.byType(NegotiatorAvatar).first).isOnline, isFalse);

    // tester.state(...).show() rather than a drag/fling gesture -- with
    // only 2 fixture listings the ListView's content may not exceed the
    // viewport, and RefreshIndicator's default physics don't reliably
    // register an overscroll-triggered refresh on short content. .show()
    // is RefreshIndicatorState's own public API for exactly this case:
    // it invokes the real onRefresh callback directly, independent of
    // scroll gesture physics. Not directly awaited -- its own Future only
    // resolves once frames are pumped forward, so awaiting it before any
    // pump() call deadlocks (nothing ever advances the animation it's
    // waiting on).
    final refresh = tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await refresh;
    await tester.pumpAndSettle();

    expect(tester.widget<NegotiatorAvatar>(find.byType(NegotiatorAvatar).first).isOnline, isTrue);
  });
}
