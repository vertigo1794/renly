// app/test/features/requirement/post_requirement_screen_test.dart
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
import 'package:renly/features/listing/listing_providers.dart' hide currentNegotiatorIdProvider;
import 'package:renly/features/listing/listing_repository.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/requirement/post_requirement_screen.dart';
import 'package:renly/features/requirement/requirement_providers.dart';
import 'package:renly/features/subscription/models/subscription_status.dart' as subscription;
import 'package:renly/features/subscription/subscription_providers.dart' as subscription_providers;

/// Never actually invoked -- see the identical class in
/// post_broadcast_screen_test.dart, which this mirrors.
class _FakeSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Symmetric fake for PostRequirementFormBody's live-preview fetch, which
/// reads listingRepositoryProvider directly in initState() -- otherwise
/// throws synchronously on the uninitialized Supabase.instance.client in
/// every test here. Defaults to empty; the preview test below seeds it with
/// one qualifying Listing.
class _FakeListingRepository extends ListingRepository {
  _FakeListingRepository([this._listings = const []]) : super(_FakeSupabaseClient());

  final List<Listing> _listings;

  @override
  Future<List<Listing>> fetchMarketplaceListings() async => _listings;
}

List<Override> _baseOverrides() => [
      listingRepositoryProvider.overrideWithValue(_FakeListingRepository()),
    ];

Widget _wrap(GoRouter router, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [..._baseOverrides(), ...overrides],
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

  testWidgets('renders all required fields', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostRequirementFormBody())),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('requirement_property_type_field')), findsOneWidget);
    expect(find.byKey(const Key('requirement_transaction_type_field')), findsOneWidget);
    expect(find.byKey(const Key('requirement_state_field')), findsOneWidget);
    expect(find.byKey(const Key('requirement_area_field')), findsOneWidget);
    expect(find.byKey(const Key('requirement_budget_min_field')), findsOneWidget);
    expect(find.byKey(const Key('requirement_budget_max_field')), findsOneWidget);
    expect(find.byKey(const Key('requirement_tenure_field')), findsOneWidget);
    expect(find.byKey(const Key('requirement_parking_bays_min_field')), findsOneWidget);
    expect(find.byKey(const Key('requirement_floor_level_min_field')), findsOneWidget);
    expect(find.byKey(const Key('requirement_furnishing_field')), findsOneWidget);
  });

  testWidgets('submitting with empty required fields shows validation errors', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostRequirementFormBody())),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(BrutalistButton, 'Find Matches'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BrutalistButton, 'Find Matches'));
    await tester.pumpAndSettle();

    expect(find.text('This field is required'), findsWidgets);
  });

  testWidgets('shows inline error when max budget is below min budget', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostRequirementFormBody())),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('requirement_area_field')), 'Petaling Jaya');
    await tester.enterText(find.byKey(const Key('requirement_budget_min_field')), '500000');
    await tester.enterText(find.byKey(const Key('requirement_budget_max_field')), '300000');

    // Unfocus before scrolling: a focused TextField schedules its own
    // "scroll into view" request, which otherwise races the explicit
    // ensureVisible() call below and can scroll the submit button back
    // out of the viewport before the tap lands.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(BrutalistButton, 'Find Matches'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BrutalistButton, 'Find Matches'));
    await tester.pumpAndSettle();

    expect(find.text('Maximum budget must be at least the minimum'), findsOneWidget);
  });

  testWidgets('shows active count and disables submit at the free-tier cap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostRequirementFormBody())),
    ]);

    await tester.pumpWidget(_wrap(router, overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      activeRequirementCountProvider('n-1').overrideWith((ref) async => 3),
      subscription_providers.subscriptionStatusProvider.overrideWith(
        (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'free')),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text("You've reached the Free plan's limit of 3 active requirements. Upgrade to Professional for unlimited requirements."), findsOneWidget);

    final button = tester.widget<BrutalistButton>(find.byType(BrutalistButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('does not block submit for a professional-tier negotiator even at 3 active requirements', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostRequirementFormBody())),
    ]);

    await tester.pumpWidget(_wrap(router, overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      activeRequirementCountProvider('n-1').overrideWith((ref) async => 3),
      subscription_providers.subscriptionStatusProvider.overrideWith(
        (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'professional')),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text("You've reached the Free plan's limit of 3 active requirements. Upgrade to Professional for unlimited requirements."), findsNothing);

    final button = tester.widget<BrutalistButton>(find.byType(BrutalistButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('shows a live match preview once a fetched candidate qualifies', (tester) async {
    final matchingListing = Listing(
      listingId: 'l-9',
      negotiatorId: 'n-9',
      title: 'Test Unit',
      description: 'd',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Johor',
      area: 'Mont Kiara',
      price: 500000,
      photoUrls: const [],
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
    );

    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostRequirementFormBody())),
    ]);

    await tester.pumpWidget(_wrap(router, overrides: [
      listingRepositoryProvider.overrideWithValue(_FakeListingRepository([matchingListing])),
    ]));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('requirement_area_field')), 'Mont Kiara');
    await tester.enterText(find.byKey(const Key('requirement_budget_min_field')), '400000');
    await tester.enterText(find.byKey(const Key('requirement_budget_max_field')), '600000');
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.text('preview_units_count'.tr(namedArgs: {'count': '1'})), findsOneWidget);
  });

  testWidgets('renders with no overflow at a realistic 360dp phone width', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostRequirementFormBody())),
    ]);

    final originalSize = tester.view.physicalSize;
    final originalRatio = tester.view.devicePixelRatio;
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.devicePixelRatio = originalRatio;
    });

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
