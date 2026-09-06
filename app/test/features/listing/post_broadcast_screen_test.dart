// app/test/features/listing/post_broadcast_screen_test.dart
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
import 'package:renly/features/listing/listing_providers.dart';
import 'package:renly/features/listing/listing_repository.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/post_broadcast_screen.dart';
import 'package:renly/features/notifications/notification_providers.dart';
import 'package:renly/features/profile/models/profile.dart';
import 'package:renly/features/profile/profile_providers.dart' hide currentNegotiatorIdProvider;
import 'package:renly/features/requirement/models/requirement.dart';
import 'package:renly/features/requirement/requirement_providers.dart' hide currentNegotiatorIdProvider;
import 'package:renly/features/requirement/requirement_repository.dart';

/// Never actually invoked -- both fake repositories below override every
/// method PostBroadcastScreen's preview fetch calls, so this client's
/// methods are never reached. It only exists to satisfy the real
/// repositories' constructors without touching Supabase.instance.client
/// (which throws synchronously in this widget-test environment, since
/// Supabase.initialize() is never called here).
class _FakeSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// PostListingFormBody's live-preview fetch reads requirementRepositoryProvider
/// directly (not boardRequirementsProvider), so that's the provider that must
/// be overridden for the preview fetch to resolve instead of silently
/// swallowing a thrown error in this test environment.
class _FakeRequirementRepository extends RequirementRepository {
  _FakeRequirementRepository() : super(_FakeSupabaseClient());

  @override
  Future<List<Requirement>> fetchBoardRequirements() async => [];
}

/// Symmetric fake for PostRequirementFormBody's live-preview fetch, which
/// reads listingRepositoryProvider directly.
class _FakeListingRepository extends ListingRepository {
  _FakeListingRepository() : super(_FakeSupabaseClient());

  @override
  Future<List<Listing>> fetchMarketplaceListings() async => [];
}

Future<void> _pumpScreen(WidgetTester tester, {required List<Override> overrides, PostBroadcastMode initialMode = PostBroadcastMode.listing, String? editListingId}) async {
  // Widened for the same reason every other tall-card/tall-form screen this
  // session needed it: the default 800x600 test surface is too short to
  // mount this screen's genuinely long form content.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => PostBroadcastScreen(initialMode: initialMode, editListingId: editListingId),
    ),
  ]);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
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
    ),
  );
  await tester.pumpAndSettle();
}

List<Override> _baseOverrides() => [
      myProfileProvider.overrideWith((ref) async => const Profile(
            negotiatorId: 'n-1',
            fullName: 'Aiman Yusof',
            verificationStatus: 'approved',
          )),
      unreadNotificationCountProvider.overrideWith((ref) => 0),
      marketplaceListingsProvider.overrideWith((ref) async => []),
      openRequirementsCountProvider.overrideWith((ref) async => 0),
      // Both forms' live-preview fetches read the repository providers
      // directly (fetchBoardRequirements/fetchMarketplaceListings), not
      // boardRequirementsProvider/marketplaceListingsProvider above -- these
      // overrides are what let the preview fetch actually succeed here
      // instead of throwing on the uninitialized Supabase.instance.client
      // and being silently swallowed.
      requirementRepositoryProvider.overrideWithValue(_FakeRequirementRepository()),
      listingRepositoryProvider.overrideWithValue(_FakeListingRepository()),
    ];

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  testWidgets('defaults to the Provide Listing tab and shows the listing form', (tester) async {
    await _pumpScreen(tester, overrides: _baseOverrides());

    expect(find.byKey(const Key('listing_title_field')), findsOneWidget);
    expect(find.byKey(const Key('requirement_property_type_field')), findsNothing);
  });

  testWidgets('initialMode requirement shows the Buyer Match form instead', (tester) async {
    await _pumpScreen(tester, overrides: _baseOverrides(), initialMode: PostBroadcastMode.requirement);

    expect(find.byKey(const Key('requirement_property_type_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_title_field')), findsNothing);
  });

  testWidgets('tapping the toggle switches the visible form and preserves typed text', (tester) async {
    await _pumpScreen(tester, overrides: _baseOverrides());

    await tester.enterText(find.byKey(const Key('listing_title_field')), 'My Draft Title');
    await tester.pumpAndSettle();

    await tester.tap(find.text('broadcast_buyer_match_tab'.tr()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('requirement_property_type_field')), findsOneWidget);
    expect(find.byKey(const Key('listing_title_field')), findsNothing);

    await tester.tap(find.text('broadcast_provide_listing_tab'.tr()));
    await tester.pumpAndSettle();

    final titleField = tester.widget<TextFormField>(find.byKey(const Key('listing_title_field')));
    expect(titleField.controller?.text, 'My Draft Title');
  });

  testWidgets('toggle is hidden entirely in edit mode', (tester) async {
    await _pumpScreen(
      tester,
      overrides: [
        ..._baseOverrides(),
        currentNegotiatorIdProvider.overrideWith((ref) => 'n-1'),
        listingDetailProvider('l-1').overrideWith((ref) async => Listing(
              listingId: 'l-1',
              negotiatorId: 'n-1',
              title: 'Existing',
              description: 'd',
              propertyType: 'apartment',
              transactionType: 'sale',
              state: 'Selangor',
              area: 'Shah Alam',
              price: 500000,
              photoUrls: const [],
              status: 'active',
              createdAt: DateTime(2024, 1, 1),
            )),
      ],
      editListingId: 'l-1',
    );

    expect(find.text('broadcast_provide_listing_tab'.tr()), findsNothing);
    expect(find.text('broadcast_buyer_match_tab'.tr()), findsNothing);
  });
}
