// app/test/features/listing/property_detail_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/core/widgets/brutalist_button.dart';
import 'package:renly/features/listing/listing_providers.dart';
import 'package:renly/features/listing/listing_repository.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/listing/property_detail_screen.dart';
import 'package:renly/features/requirement/models/requirement.dart';
import 'package:renly/features/requirement/requirement_providers.dart' hide currentNegotiatorIdProvider;
import 'package:renly/features/requirement/requirement_repository.dart';
import 'package:renly/features/subscription/models/subscription_status.dart' as subscription;
import 'package:renly/features/subscription/subscription_providers.dart' as subscription_providers;

/// Never actually invoked -- see the identical class in
/// post_broadcast_screen_test.dart, which this mirrors.
class _FakeSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// _loadBestMatchScore reads listingRepositoryProvider.fetchListingById
/// directly (not listingDetailProvider, which _wrap already overrides for
/// the main widget tree) -- this fake makes that second, independent
/// fetch resolve instead of throwing on the uninitialized Supabase client.
class _FakeListingRepositoryForMatchScore extends ListingRepository {
  _FakeListingRepositoryForMatchScore(this._listing) : super(_FakeSupabaseClient());

  final Listing _listing;

  @override
  Future<Listing> fetchListingById(String listingId) async => _listing;
}

/// Symmetric fake for _loadBestMatchScore's fetchOwnRequirements call.
class _FakeRequirementRepositoryForMatchScore extends RequirementRepository {
  _FakeRequirementRepositoryForMatchScore([this._requirements = const []]) : super(_FakeSupabaseClient());

  final List<Requirement> _requirements;

  @override
  Future<List<Requirement>> fetchOwnRequirements(String negotiatorId) async => _requirements;
}

final _fixtureListing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'The Vertex Residency',
  description: 'A modern apartment with lots of light.',
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
);

final _withdrawnListingOwnedByN1 = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'The Vertex Residency',
  description: 'A modern apartment with lots of light.',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  price: 1250000,
  bedrooms: 3,
  bathrooms: 2,
  photoUrls: [],
  status: 'withdrawn',
  createdAt: DateTime(2024, 1, 1),
);

const _fixtureOwner = ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345');

Widget _wrap(GoRouter router, {String currentNegotiatorId = 'n-2', Listing? listing, List<Override> extraOverrides = const []}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue(currentNegotiatorId),
      listingDetailProvider.overrideWith((ref, listingId) async => listing ?? _fixtureListing),
      listingOwnerProvider.overrideWith((ref, negotiatorId) async => _fixtureOwner),
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

  testWidgets('renders title, price, description, and location', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('The Vertex Residency'), findsOneWidget);
    expect(find.text('RM 1,250,000'), findsOneWidget);
    expect(find.text('A modern apartment with lots of light.'), findsOneWidget);
    // Location shows area AND state, not area alone.
    expect(find.text('Petaling Jaya, Selangor'), findsOneWidget);
    expect(find.text('Aiman Yusof'), findsOneWidget);
    expect(find.text('REN: 12345'), findsOneWidget);
  });

  testWidgets('shows status-change actions when viewer is the owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(router, currentNegotiatorId: 'n-1'));
    await tester.pumpAndSettle();

    expect(find.text('Mark as Sold'), findsOneWidget);
  });

  testWidgets('hides status-change actions when viewer is not the owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(router, currentNegotiatorId: 'n-2'));
    await tester.pumpAndSettle();

    expect(find.text('Mark as Sold'), findsNothing);
  });

  testWidgets('disables the reactivate button at the free-tier active-listing cap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      currentNegotiatorId: 'n-1',
      listing: _withdrawnListingOwnedByN1,
      extraOverrides: [
        activeListingCountProvider('n-1').overrideWith((ref) async => 3),
        subscription_providers.subscriptionStatusProvider.overrideWith(
          (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'free')),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text("You've reached the Free plan's limit of 3 active listings. Upgrade to Professional for unlimited listings."), findsOneWidget);

    final reactivateButton = tester.widget<BrutalistButton>(
      find.widgetWithText(BrutalistButton, 'property_reactivate'.tr()),
    );
    expect(reactivateButton.onPressed, isNull);
  });

  testWidgets('keeps the reactivate button enabled for a free-tier owner under the cap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      currentNegotiatorId: 'n-1',
      listing: _withdrawnListingOwnedByN1,
      extraOverrides: [
        activeListingCountProvider('n-1').overrideWith((ref) async => 2),
        subscription_providers.subscriptionStatusProvider.overrideWith(
          (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'free')),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text("You've reached the Free plan's limit of 3 active listings. Upgrade to Professional for unlimited listings."), findsNothing);

    final reactivateButton = tester.widget<BrutalistButton>(
      find.widgetWithText(BrutalistButton, 'property_reactivate'.tr()),
    );
    expect(reactivateButton.onPressed, isNotNull);
  });

  testWidgets('shows the real match badge when the viewer has a qualifying open requirement', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    const matchingRequirement = Requirement(
      requirementId: 'r-1',
      negotiatorId: 'n-2',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Petaling Jaya',
      budgetMin: 1000000,
      budgetMax: 1500000,
      bedrooms: 3,
      photoUrls: [],
      status: 'open',
    );

    await tester.pumpWidget(_wrap(
      router,
      currentNegotiatorId: 'n-2',
      extraOverrides: [
        listingRepositoryProvider.overrideWithValue(_FakeListingRepositoryForMatchScore(_fixtureListing)),
        requirementRepositoryProvider.overrideWithValue(_FakeRequirementRepositoryForMatchScore([matchingRequirement])),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('property_match_badge'.tr(namedArgs: {'score': '100'})), findsOneWidget);
  });

  testWidgets('hides the match badge for the listing owner viewing their own listing', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      currentNegotiatorId: 'n-1',
      extraOverrides: [
        listingRepositoryProvider.overrideWithValue(_FakeListingRepositoryForMatchScore(_fixtureListing)),
        requirementRepositoryProvider.overrideWithValue(_FakeRequirementRepositoryForMatchScore()),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('MATCH'), findsNothing);
  });

  testWidgets('shows real commission split and price-per-sqft in the deal terms banner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    final listingWithSplit = Listing(
      listingId: 'l-1',
      negotiatorId: 'n-1',
      title: 'The Vertex Residency',
      description: 'A modern apartment with lots of light.',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Petaling Jaya',
      price: 1000000,
      builtUpSqft: 1000,
      photoUrls: const [],
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
      commissionSplitPercent: 50,
    );

    await tester.pumpWidget(_wrap(router, listing: listingWithSplit));
    await tester.pumpAndSettle();

    expect(find.text('50/50'), findsOneWidget);
    expect(find.text('property_price_per_sqft'.tr(namedArgs: {'value': '1000'})), findsOneWidget);
  });
}
