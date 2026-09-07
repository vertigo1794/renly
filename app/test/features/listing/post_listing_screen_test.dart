// app/test/features/listing/post_listing_screen_test.dart
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
import 'package:renly/features/listing/listing_drafts_provider.dart';
import 'package:renly/features/listing/listing_providers.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_draft.dart';
import 'package:renly/features/listing/post_listing_screen.dart';
import 'package:renly/core/widgets/brutalist_button.dart';
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

/// PostListingFormBody's live-preview fetch reads requirementRepositoryProvider
/// directly in initState(), which otherwise throws synchronously on the
/// uninitialized Supabase.instance.client in every test here (silently
/// swallowed, but noisy via debugPrint) -- overriding it below is what lets
/// the fetch actually resolve. Defaults to empty; the preview test below
/// seeds it with one qualifying Requirement.
class _FakeRequirementRepository extends RequirementRepository {
  _FakeRequirementRepository([this._requirements = const []]) : super(_FakeSupabaseClient());

  final List<Requirement> _requirements;

  @override
  Future<List<Requirement>> fetchBoardRequirements() async => _requirements;
}

List<Override> _baseOverrides() => [
      requirementRepositoryProvider.overrideWithValue(_FakeRequirementRepository()),
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
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostListingFormBody())),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('listing_title_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_description_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_property_type_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_transaction_type_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_state_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_area_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_price_field')), findsOneWidget);
  });

  testWidgets('submitting with empty required fields shows validation errors', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostListingFormBody())),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    // ensureVisible rather than a fixed drag offset: the form grew taller
    // once the commission-split/title-verified/exclusive-mandate fields and
    // the Save as Draft button were added (My Inventory Premium Restyle), so
    // a hardcoded scroll distance would under-scroll and miss the button.
    await tester.ensureVisible(find.widgetWithText(BrutalistButton, 'Post Now'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BrutalistButton, 'Post Now'));
    await tester.pumpAndSettle();

    expect(find.text('This field is required'), findsWidgets);
  });

  testWidgets('shows active count and disables submit at the free-tier cap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostListingFormBody())),
    ]);

    await tester.pumpWidget(_wrap(router, overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      activeListingCountProvider('n-1').overrideWith((ref) async => 3),
      subscription_providers.subscriptionStatusProvider.overrideWith(
        (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'free')),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text("You've reached the Free plan's limit of 3 active listings. Upgrade to Professional for unlimited listings."), findsOneWidget);

    // find.byType(BrutalistButton) alone now matches 2 widgets (Post Now +
    // Save as Draft), so the primary submit button must be looked up by its
    // own label.
    final button = tester.widget<BrutalistButton>(find.widgetWithText(BrutalistButton, 'Post Now'));
    expect(button.onPressed, isNull);
  });

  testWidgets('does not block submit for a professional-tier negotiator even at 3 active listings', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostListingFormBody())),
    ]);

    await tester.pumpWidget(_wrap(router, overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      activeListingCountProvider('n-1').overrideWith((ref) async => 3),
      subscription_providers.subscriptionStatusProvider.overrideWith(
        (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'professional')),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text("You've reached the Free plan's limit of 3 active listings. Upgrade to Professional for unlimited listings."), findsNothing);

    final button = tester.widget<BrutalistButton>(find.widgetWithText(BrutalistButton, 'Post Now'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('edit mode pre-fills fields from the existing listing and shows Save Changes', (tester) async {
    final existingListing = Listing(
      listingId: 'l-1',
      negotiatorId: 'n-1',
      title: 'Existing Title',
      description: 'Existing description',
      propertyType: 'house',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Shah Alam',
      price: 500000,
      bedrooms: 4,
      bathrooms: 3,
      photoUrls: const [],
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
    );

    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: PostListingFormBody(editListingId: 'l-1')),
      ),
    ]);

    await tester.pumpWidget(_wrap(router, overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      listingDetailProvider('l-1').overrideWith((ref) async => existingListing),
      subscription_providers.subscriptionStatusProvider.overrideWith(
        (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'professional')),
      ),
    ]));
    await tester.pumpAndSettle();

    final titleField = tester.widget<TextFormField>(find.byKey(const Key('listing_title_field')));
    expect(titleField.controller?.text, 'Existing Title');
    expect(find.text('listing_save_changes'.tr()), findsOneWidget);
    expect(find.text('listing_post_now'.tr()), findsNothing);
  });

  testWidgets('shows a live match preview once a fetched candidate qualifies', (tester) async {
    final matchingRequirement = Requirement(
      requirementId: 'r-1',
      negotiatorId: 'n-2',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Johor',
      area: 'Mont Kiara',
      budgetMin: 400000,
      budgetMax: 600000,
      photoUrls: const [],
      status: 'open',
    );

    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostListingFormBody())),
    ]);

    await tester.pumpWidget(_wrap(router, overrides: [
      requirementRepositoryProvider.overrideWithValue(_FakeRequirementRepository([matchingRequirement])),
    ]));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('listing_area_field')), 'Mont Kiara');
    await tester.enterText(find.byKey(const Key('listing_price_field')), '500000');
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.text('preview_units_count'.tr(namedArgs: {'count': '1'})), findsOneWidget);
  });

  testWidgets('renders the new property-attribute fields', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostListingFormBody())),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('listing_tenure_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_maintenance_fee_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_parking_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_floor_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_furnishing_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_total_commission_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_keys_on_hand_switch')), findsOneWidget);
    expect(find.byKey(const Key('listing_protected_co_broke_reg_switch')), findsOneWidget);
  });

  testWidgets('edit mode pre-fills the new property-attribute fields', (tester) async {
    final existingListing = Listing(
      listingId: 'l-1',
      negotiatorId: 'n-1',
      title: 'Existing Title',
      description: 'Existing description',
      propertyType: 'house',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Shah Alam',
      price: 500000,
      photoUrls: const [],
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
      maintenanceFeeMyr: 580,
      tenure: 'freehold',
      parkingBays: 2,
      floorLevel: 38,
      furnishingStatus: 'furnished',
      keysOnHand: true,
      protectedCoBrokeReg: true,
      totalAgencyCommissionPercent: 3,
    );

    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: PostListingFormBody(editListingId: 'l-1')),
      ),
    ]);

    await tester.pumpWidget(_wrap(router, overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      listingDetailProvider('l-1').overrideWith((ref) async => existingListing),
      subscription_providers.subscriptionStatusProvider.overrideWith(
        (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'professional')),
      ),
    ]));
    await tester.pumpAndSettle();

    final maintenanceField = tester.widget<TextFormField>(find.byKey(const Key('listing_maintenance_fee_field')));
    expect(maintenanceField.controller?.text, '580.0');
    final keysOnHandSwitch = tester.widget<SwitchListTile>(find.byKey(const Key('listing_keys_on_hand_switch')));
    expect(keysOnHandSwitch.value, true);
  });

  testWidgets('Save as Draft preserves tenure, maintenance fee, and keys-on-hand, and resuming restores them', (tester) async {
    // A real ProviderContainer (rather than just a ProviderScope) so the
    // saved draft can be read back directly via
    // container.read(listingDraftsProvider) without depending on
    // navigation to '/my-inventory' actually working in this test.
    final container = ProviderContainer(overrides: _baseOverrides());
    addTearDown(container.dispose);
    // Eagerly instantiate the drafts notifier (and let its async
    // SharedPreferences-backed _load() settle below) BEFORE the form
    // itself first touches it in _saveAsDraft(). Without this, _load()
    // racing a same-tick add() can finish AFTER add() and clobber it back
    // to the empty list it read at construction time -- exactly what a
    // real app avoids by having some other already-mounted screen (My
    // Inventory) watch this provider well before the user ever reaches
    // Post Listing's Save as Draft button.
    container.read(listingDraftsProvider);

    Widget wrapWithContainer(GoRouter router) {
      return UncontrolledProviderScope(
        container: container,
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

    final saveRouter = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: PostListingFormBody())),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Scaffold(body: Text('inventory'))),
    ]);

    await tester.pumpWidget(wrapWithContainer(saveRouter));
    await tester.pumpAndSettle();

    // One representative field from each Dart-type category ListingDraft
    // stores: a String-backed dropdown (tenure), a numeric text field
    // (maintenance fee), and a boolean toggle (keys on hand).
    await tester.enterText(find.byKey(const Key('listing_title_field')), 'Draft With New Fields');
    await tester.enterText(find.byKey(const Key('listing_maintenance_fee_field')), '250');

    await tester.ensureVisible(find.byKey(const Key('listing_tenure_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('listing_tenure_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('listing_tenure_freehold'.tr()).last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('listing_keys_on_hand_switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('listing_keys_on_hand_switch')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('listing_save_as_draft'.tr()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('listing_save_as_draft'.tr()));
    await tester.pumpAndSettle();

    final drafts = container.read(listingDraftsProvider);
    expect(drafts, hasLength(1));
    final draft = drafts.single;
    expect(draft.tenure, 'freehold');
    expect(draft.maintenanceFeeMyr, '250');
    expect(draft.keysOnHand, isTrue);

    // Resuming the just-saved draft restores those same 3 fields into a
    // fresh form -- proves the round trip through toJson/fromJson (real
    // SharedPreferences persistence) and initState's hydration, not just
    // the in-memory ListingDraft object.
    final rawPersisted = draft.toJson();
    final reloadedDraft = ListingDraft.fromJson(rawPersisted);

    final resumeRouter = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => Scaffold(body: PostListingFormBody(initialDraft: reloadedDraft))),
    ]);
    await tester.pumpWidget(wrapWithContainer(resumeRouter));
    await tester.pumpAndSettle();

    final resumedMaintenanceField = tester.widget<TextFormField>(find.byKey(const Key('listing_maintenance_fee_field')));
    expect(resumedMaintenanceField.controller?.text, '250');

    expect(
      find.descendant(of: find.byKey(const Key('listing_tenure_field')), matching: find.text('listing_tenure_freehold'.tr())),
      findsOneWidget,
    );

    final resumedKeysOnHandSwitch = tester.widget<SwitchListTile>(find.byKey(const Key('listing_keys_on_hand_switch')));
    expect(resumedKeysOnHandSwitch.value, isTrue);
  });
}
