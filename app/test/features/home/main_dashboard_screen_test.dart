import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/home/main_dashboard_screen.dart';
import 'package:renly/features/listing/listing_providers.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/matching/matching_providers.dart' hide currentNegotiatorIdProvider;
import 'package:renly/features/matching/models/match_candidate.dart';
import 'package:renly/features/notifications/notification_providers.dart';
import 'package:renly/features/profile/models/profile.dart';
import 'package:renly/features/profile/profile_providers.dart' hide currentNegotiatorIdProvider;
import 'package:renly/features/collaboration/cobroke_request_providers.dart' hide currentNegotiatorIdProvider;
import 'package:renly/features/requirement/models/requirement.dart';

final _listing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'Modern Villa',
  description: 'd',
  propertyType: 'house',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Downtown',
  price: 2450000,
  bedrooms: 4,
  bathrooms: 3,
  photoUrls: [],
  status: 'active',
  createdAt: DateTime(2024, 1, 1),
);

final _requirement = Requirement(
  requirementId: 'r-1',
  negotiatorId: 'n-2',
  propertyType: 'house',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Downtown',
  budgetMin: 2000000,
  budgetMax: 3000000,
  photoUrls: [],
  status: 'open',
);

final _matchCandidate = MatchCandidate(
  matchId: 'm-1',
  score: 92,
  listing: _listing,
  requirement: _requirement,
  listingOwner: const ListingOwner(fullName: 'Aiman Yusof', renNumber: '48210'),
  requirementOwner: const ListingOwner(fullName: 'Julian Danial', renNumber: '34812', agencyName: 'IQI Global'),
);

// A match on a DIFFERENT negotiator's listing (negotiatorId 'n-9', not the
// signed-in 'n-1'). Used to prove the Radar's client-side .where() filter
// actually excludes matches that aren't on the current negotiator's own
// listings, rather than just happening to include the one match that is.
final _otherNegotiatorListing = Listing(
  listingId: 'l-2',
  negotiatorId: 'n-9',
  title: 'Lakeside Bungalow',
  description: 'd',
  propertyType: 'house',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Bangsar',
  price: 1800000,
  bedrooms: 3,
  bathrooms: 2,
  photoUrls: [],
  status: 'active',
  createdAt: DateTime(2024, 1, 1),
);

final _otherRequirement = Requirement(
  requirementId: 'r-2',
  negotiatorId: 'n-3',
  propertyType: 'house',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Bangsar',
  budgetMin: 1500000,
  budgetMax: 2000000,
  photoUrls: [],
  status: 'open',
);

final _otherNegotiatorMatchCandidate = MatchCandidate(
  matchId: 'm-2',
  score: 80,
  listing: _otherNegotiatorListing,
  requirementOwner: const ListingOwner(fullName: 'Siti Aminah', renNumber: '99999', agencyName: 'PropNex'),
  requirement: _otherRequirement,
  listingOwner: const ListingOwner(fullName: 'Farid Iskandar', renNumber: '77777'),
);

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (context, state) => const MainDashboardScreen()),
    GoRoute(path: '/post-listing', builder: (context, state) => const Text('post-listing-screen')),
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

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  testWidgets('renders welcome header, quick actions, and a listing card', (tester) async {
    await _pumpDashboard(
      tester,
      overrides: [
        myProfileProvider.overrideWith((ref) async => const Profile(
              negotiatorId: 'n-1',
              fullName: 'Aiman Yusof',
              renNumber: '48210',
              verificationStatus: 'approved',
            )),
        marketplaceListingsProvider.overrideWith((ref) async => [_listing]),
        currentNegotiatorIdProvider.overrideWithValue('n-1'),
        myListingsProvider.overrideWith((ref, negotiatorId) async => [_listing]),
        receivedRequestsProvider.overrideWith((ref) async => []),
        unreadNotificationCountProvider.overrideWith((ref) => 2),
        myMatchesProvider.overrideWith((ref) async => [_matchCandidate]),
        marketPulseProvider.overrideWith((ref, negotiatorId) async => (area: 'Mont Kiara', count: 3)),
      ],
    );

    expect(find.textContaining('Aiman Yusof'), findsOneWidget);
    expect(find.textContaining('REN 48210'), findsOneWidget);
    expect(find.text('Modern Villa'), findsOneWidget);
    expect(find.textContaining('1 Listings'), findsOneWidget);

    await tester.tap(find.text('dashboard_quick_action_post_listing'.tr()));
    await tester.pumpAndSettle();
    expect(find.text('post-listing-screen'), findsOneWidget);
  });

  testWidgets('hides REN pill when profile has no renNumber', (tester) async {
    await _pumpDashboard(
      tester,
      overrides: [
        myProfileProvider.overrideWith((ref) async => const Profile(
              negotiatorId: 'n-1',
              fullName: 'Aiman Yusof',
              verificationStatus: 'approved',
            )),
        marketplaceListingsProvider.overrideWith((ref) async => []),
        currentNegotiatorIdProvider.overrideWithValue('n-1'),
        myListingsProvider.overrideWith((ref, negotiatorId) async => []),
        receivedRequestsProvider.overrideWith((ref) async => []),
        unreadNotificationCountProvider.overrideWith((ref) => 0),
        // Empty/null here (not the shared _matchCandidate fixture): this test
        // asserts findsNothing for any "REN" text (checking the header pill
        // is hidden), and the Radar card would otherwise render the match's
        // "REN 34812" requirementOwner text and break that unrelated
        // assertion. Still overridden (not left to the real repository)
        // because the screen unconditionally watches myMatchesProvider
        // regardless of currentNegotiatorIdProvider -- myMatchesProvider
        // takes no negotiatorId parameter at all; it's the Radar's own
        // client-side .where() filter that uses negotiatorId, not the
        // provider itself.
        myMatchesProvider.overrideWith((ref) async => []),
        marketPulseProvider.overrideWith((ref, negotiatorId) async => null),
      ],
    );

    expect(find.textContaining('REN'), findsNothing);
    expect(find.text('dashboard_quick_action_market'.tr()), findsOneWidget);
    expect(find.text('dashboard_quick_action_my_inventory'.tr()), findsOneWidget);
    expect(find.textContaining('· 0'), findsNothing);
  });

  testWidgets('shows Co-Broking Radar for matches on my own listings only', (tester) async {
    await _pumpDashboard(
      tester,
      overrides: [
        myProfileProvider.overrideWith((ref) async => const Profile(
              negotiatorId: 'n-1',
              fullName: 'Aiman Yusof',
              renNumber: '48210',
              verificationStatus: 'approved',
            )),
        marketplaceListingsProvider.overrideWith((ref) async => []),
        currentNegotiatorIdProvider.overrideWithValue('n-1'),
        myListingsProvider.overrideWith((ref, negotiatorId) async => []),
        receivedRequestsProvider.overrideWith((ref) async => []),
        unreadNotificationCountProvider.overrideWith((ref) => 0),
        myMatchesProvider.overrideWith((ref) async => [_matchCandidate, _otherNegotiatorMatchCandidate]),
        marketPulseProvider.overrideWith((ref, negotiatorId) async => (area: 'Mont Kiara', count: 3)),
      ],
    );

    expect(find.text('dashboard_radar_title'.tr()), findsOneWidget);
    expect(find.textContaining('92%'), findsOneWidget);
    expect(find.textContaining('IQI Global'), findsOneWidget);
    expect(find.textContaining('Mont Kiara'), findsWidgets);
    // Negative case: the match on 'n-9's listing must be filtered out by the
    // Radar's own-listings-only .where(), so its requirement owner and area
    // never render, even though it was included in myMatchesProvider's list.
    expect(find.textContaining('Siti Aminah'), findsNothing);
    expect(find.textContaining('Bangsar'), findsNothing);
  });

  testWidgets('hides Co-Broking Radar and Market Pulse when there are no matches', (tester) async {
    await _pumpDashboard(
      tester,
      overrides: [
        myProfileProvider.overrideWith((ref) async => const Profile(
              negotiatorId: 'n-1',
              fullName: 'Aiman Yusof',
              verificationStatus: 'approved',
            )),
        marketplaceListingsProvider.overrideWith((ref) async => []),
        currentNegotiatorIdProvider.overrideWithValue('n-1'),
        myListingsProvider.overrideWith((ref, negotiatorId) async => []),
        receivedRequestsProvider.overrideWith((ref) async => []),
        unreadNotificationCountProvider.overrideWith((ref) => 0),
        myMatchesProvider.overrideWith((ref) async => []),
        marketPulseProvider.overrideWith((ref, negotiatorId) async => null),
      ],
    );

    expect(find.text('dashboard_radar_title'.tr()), findsNothing);
    expect(find.text('dashboard_market_pulse_live'.tr()), findsNothing);
  });
}
