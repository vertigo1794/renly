// app/test/features/listing/property_detail_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/core/widgets/brutalist_button.dart';
import 'package:renly/features/listing/listing_providers.dart';
import 'package:renly/features/listing/listing_repository.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/listing/property_detail_screen.dart';
import 'package:renly/features/matching/matching_providers.dart' hide currentNegotiatorIdProvider;
import 'package:renly/features/ratings/models/rating.dart';
import 'package:renly/features/ratings/models/rating_candidate.dart';
import 'package:renly/features/ratings/rating_providers.dart' hide currentNegotiatorIdProvider;
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

/// Only needed by the photo-counter test below, which is the one test in
/// this file that actually populates `photoUrls` -- `ListingPhoto` reads
/// `listingRepositoryProvider.createSignedUrl` directly in its build
/// method (via SignedPhoto), which throws synchronously on the
/// uninitialized Supabase client otherwise. The bogus URL never actually
/// resolves an image; SignedPhoto's own errorBuilder falls back to a
/// placeholder, which is all this test needs.
class _FakeListingRepositoryForPhotos extends ListingRepository {
  _FakeListingRepositoryForPhotos() : super(_FakeSupabaseClient());

  @override
  Future<String> createSignedUrl(String path) async => 'https://example.invalid/$path';
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

    // Scoped to the deal-terms banner's own split badge: since Task 8, the
    // Co-Broking Terms card also renders a "50/50" split badge in its own
    // header (a second, deliberate showing of the same ratio, distinct from
    // this deal-terms banner's at-a-glance badge) whenever
    // commissionSplitPercent is set. Scoping via the badge's Key keeps this
    // assertion specific to the banner's own rendering, so a regression
    // there is still caught even if the co-broking card keeps working.
    expect(
      find.descendant(of: find.byKey(const Key('deal_terms_split_badge')), matching: find.text('50/50')),
      findsOneWidget,
    );
    expect(find.text('property_price_per_sqft'.tr(namedArgs: {'value': '1000'})), findsOneWidget);
  });

  testWidgets('shows the exclusive-mandate badge exactly once, from the hero header only', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    final exclusiveMandateListing = Listing(
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
      photoUrls: const [],
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
      exclusiveMandate: true,
    );

    await tester.pumpWidget(_wrap(router, listing: exclusiveMandateListing));
    await tester.pumpAndSettle();

    expect(find.text('inventory_badge_exclusive_mandate'.tr()), findsOneWidget);
  });

  testWidgets('shows the real Co-Broking Terms card when a split or total commission is set', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    final listingWithTerms = Listing(
      listingId: 'l-1',
      negotiatorId: 'n-1',
      title: 'The Vertex Residency',
      description: 'A modern apartment with lots of light.',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Petaling Jaya',
      price: 1250000,
      photoUrls: const [],
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
      commissionSplitPercent: 50,
      totalAgencyCommissionPercent: 3,
    );

    await tester.pumpWidget(_wrap(router, listing: listingWithTerms));
    await tester.pumpAndSettle();

    expect(find.text('property_co_broking_terms_title'.tr()), findsOneWidget);
    expect(find.text('property_total_commission_row'.tr(namedArgs: {'percent': '3'})), findsOneWidget);
    expect(find.text('RM 37500'), findsOneWidget);
  });

  testWidgets('hides the Co-Broking Terms card when neither split nor total commission is set', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('property_co_broking_terms_title'.tr()), findsNothing);
  });

  testWidgets('shows keys-on-hand and protected-co-broke-reg badges only when true', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    final listingWithBadges = Listing(
      listingId: 'l-1',
      negotiatorId: 'n-1',
      title: 'The Vertex Residency',
      description: 'A modern apartment with lots of light.',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Petaling Jaya',
      price: 1250000,
      photoUrls: const [],
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
      keysOnHand: true,
    );

    await tester.pumpWidget(_wrap(router, listing: listingWithBadges));
    await tester.pumpAndSettle();

    expect(find.text('property_badge_keys_on_hand'.tr()), findsOneWidget);
    expect(find.text('property_badge_protected_co_broke_reg'.tr()), findsNothing);
  });

  testWidgets('hides the rating row entirely when the negotiator has no ratings yet', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(router, extraOverrides: [
      ratingsForNegotiatorProvider('n-1').overrideWith((ref) async => []),
    ]));
    await tester.pumpAndSettle();

    // Per the design doc: an empty (or still-loading) candidate list means
    // NO rating row at all -- no star icon, no fabricated "New Agent"
    // placeholder standing in for a real average.
    expect(find.text('property_no_ratings_short'.tr()), findsNothing);
    expect(find.byIcon(PhosphorIcons.star(PhosphorIconsStyle.fill)), findsNothing);
    expect(find.text('property_message_button'.tr()), findsOneWidget);
  });

  testWidgets('shows the real computed average rating on the agent card when ratings exist', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    final ratingCandidates = [
      RatingCandidate(
        rating: Rating(
          ratingId: 'r-1',
          agreementId: 'a-1',
          raterId: 'n-2',
          ratedId: 'n-1',
          stars: 5,
          createdAt: DateTime(2024, 1, 1),
        ),
        rater: const ListingOwner(fullName: 'Rater One', renNumber: '11111'),
      ),
      RatingCandidate(
        rating: Rating(
          ratingId: 'r-2',
          agreementId: 'a-2',
          raterId: 'n-3',
          ratedId: 'n-1',
          stars: 4,
          createdAt: DateTime(2024, 1, 2),
        ),
        rater: const ListingOwner(fullName: 'Rater Two', renNumber: '22222'),
      ),
      RatingCandidate(
        rating: Rating(
          ratingId: 'r-3',
          agreementId: 'a-3',
          raterId: 'n-4',
          ratedId: 'n-1',
          stars: 4,
          createdAt: DateTime(2024, 1, 3),
        ),
        rater: const ListingOwner(fullName: 'Rater Three', renNumber: '33333'),
      ),
    ];

    await tester.pumpWidget(_wrap(router, extraOverrides: [
      ratingsForNegotiatorProvider('n-1').overrideWith((ref) async => ratingCandidates),
    ]));
    await tester.pumpAndSettle();

    // Same formula as ProfileScreen's _TrustScoreCard: average stars,
    // 1-decimal, plus the candidate count in parens.
    final average = ratingCandidates.map((c) => c.rating.stars).reduce((a, b) => a + b) / ratingCandidates.length;
    expect(find.text('${average.toStringAsFixed(1)} (${ratingCandidates.length})'), findsOneWidget);
    expect(find.byIcon(PhosphorIcons.star(PhosphorIconsStyle.fill)), findsOneWidget);
  });

  testWidgets('disables Request Co-Broke when the viewer has no qualifying match for this listing', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      currentNegotiatorId: 'n-2',
      extraOverrides: [
        matchesForListingProvider('l-1').overrideWith((ref) async => []),
        ratingsForNegotiatorProvider('n-1').overrideWith((ref) async => []),
      ],
    ));
    await tester.pumpAndSettle();

    final button = tester.widget<BrutalistButton>(find.widgetWithText(BrutalistButton, 'cobroke_request_send'.tr()));
    expect(button.onPressed, isNull);
  });

  testWidgets('updates the photo counter to the real current page as the hero carousel is swiped', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    final threePhotoListing = Listing(
      listingId: 'l-1',
      negotiatorId: 'n-1',
      title: 'The Vertex Residency',
      description: 'A modern apartment with lots of light.',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Petaling Jaya',
      price: 1250000,
      photoUrls: const ['photo-1.jpg', 'photo-2.jpg', 'photo-3.jpg'],
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
    );

    await tester.pumpWidget(_wrap(
      router,
      listing: threePhotoListing,
      extraOverrides: [
        listingRepositoryProvider.overrideWithValue(_FakeListingRepositoryForPhotos()),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('property_photo_counter'.tr(namedArgs: {'current': '1', 'total': '3'})), findsOneWidget);

    // Directly drive the PageView to page index 1 (drag gesture distance is
    // brittle across viewport sizes) -- same approach as jumping/animating
    // a PageController from within a test.
    final pageView = tester.widget<PageView>(find.byType(PageView));
    pageView.controller!.jumpToPage(1);
    await tester.pumpAndSettle();

    expect(find.text('property_photo_counter'.tr(namedArgs: {'current': '2', 'total': '3'})), findsOneWidget);
    expect(find.text('property_photo_counter'.tr(namedArgs: {'current': '1', 'total': '3'})), findsNothing);
  });

  testWidgets('shows the same RM commission-share amount in the deal-terms banner and the co-broking terms card for a fractional split', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    // 52.5% split, reachable via the form's free-text Custom field. Rounded
    // to 53 for display in both cards' own "X/Y" ratio -- the RM figure in
    // both cards must be computed off that SAME rounded 53, not the raw
    // 52.5, or the two cards show two different amounts for one fact.
    final fractionalSplitListing = Listing(
      listingId: 'l-1',
      negotiatorId: 'n-1',
      title: 'The Vertex Residency',
      description: 'A modern apartment with lots of light.',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Petaling Jaya',
      price: 1000000,
      photoUrls: const [],
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
      commissionSplitPercent: 52.5,
    );

    await tester.pumpWidget(_wrap(router, listing: fractionalSplitListing));
    await tester.pumpAndSettle();

    // 1,000,000 * 53 / 100 = 530,000 -- once in the deal-terms banner's
    // split badge, once in the co-broking terms card's "your share" row.
    expect(find.text('RM 530000'), findsNWidgets(2));
    // Never the unrounded-fraction figure (1,000,000 * 52.5 / 100 = 525,000).
    expect(find.text('RM 525000'), findsNothing);
  });

  testWidgets('renders a fully-populated listing at a realistic phone width with no RenderFlex overflow', (tester) async {
    // The default 800x600 test surface is wide enough to hide the overflows
    // this fixture is meant to catch -- a real phone portrait width (and a
    // tall-enough height to fit the whole scrollable column without needing
    // to actually scroll) is required to reproduce them.
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    // Every optional field populated (all 8 new property attributes, plus
    // bedrooms/bathrooms/builtUpSqft), a long title, and a real fractional
    // commission split -- so every optional row this milestone added is
    // actually rendered and exercised.
    final fullyPopulatedListing = Listing(
      listingId: 'l-1',
      negotiatorId: 'n-1',
      title: 'The Ultra Premium Vertex Grand Residency Sky Villas Tower B Penthouse Collection',
      description: 'A very spacious, fully renovated unit with premium finishes throughout, close to schools, transit, and shopping.',
      propertyType: 'condominium',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Petaling Jaya',
      price: 2350000,
      bedrooms: 4,
      bathrooms: 3,
      builtUpSqft: 2200,
      photoUrls: const [],
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
      commissionSplitPercent: 52.5,
      titleVerified: true,
      exclusiveMandate: true,
      maintenanceFeeMyr: 850,
      tenure: 'freehold',
      parkingBays: 3,
      floorLevel: 28,
      furnishingStatus: 'partially_furnished',
      keysOnHand: true,
      protectedCoBrokeReg: true,
      totalAgencyCommissionPercent: 3.4,
    );

    final longNameOwner = const ListingOwner(
      fullName: 'Mohammad Aliff Iskandar bin Abdullah Al-Hafiz',
      renNumber: '9988776',
      agencyName: 'Prestige International Property Consultants Sdn Bhd',
      verificationStatus: 'approved',
    );

    final ratingCandidates = [
      RatingCandidate(
        rating: Rating(
          ratingId: 'r-1',
          agreementId: 'a-1',
          raterId: 'n-2',
          ratedId: 'n-1',
          stars: 5,
          createdAt: DateTime(2024, 1, 1),
        ),
        rater: const ListingOwner(fullName: 'Rater One', renNumber: '11111'),
      ),
      RatingCandidate(
        rating: Rating(
          ratingId: 'r-2',
          agreementId: 'a-2',
          raterId: 'n-3',
          ratedId: 'n-1',
          stars: 4,
          createdAt: DateTime(2024, 1, 2),
        ),
        rater: const ListingOwner(fullName: 'Rater Two', renNumber: '22222'),
      ),
    ];

    await tester.pumpWidget(_wrap(
      router,
      currentNegotiatorId: 'n-2',
      listing: fullyPopulatedListing,
      extraOverrides: [
        listingOwnerProvider.overrideWith((ref, negotiatorId) async => longNameOwner),
        ratingsForNegotiatorProvider('n-1').overrideWith((ref) async => ratingCandidates),
        matchesForListingProvider('l-1').overrideWith((ref) async => []),
      ],
    ));
    await tester.pumpAndSettle();

    // No RenderFlex overflow (or any other) exception was reported while
    // pumping/laying out the fully-populated fixture above.
    expect(tester.takeException(), isNull);

    // Sanity checks that the populated rows actually rendered (a screen
    // that silently dropped a row would pass the exception check above for
    // the wrong reason).
    expect(find.textContaining('CONDOMINIUM'), findsOneWidget);
    expect(find.text('property_co_broking_terms_title'.tr()), findsOneWidget);
    expect(find.text('Mohammad Aliff Iskandar bin Abdullah Al-Hafiz'), findsOneWidget);
  });
}
