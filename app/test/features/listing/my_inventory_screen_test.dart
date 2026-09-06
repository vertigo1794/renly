import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/collaboration/cobroke_request_providers.dart' hide currentNegotiatorIdProvider;
import 'package:renly/features/collaboration/models/cobroke_request.dart';
import 'package:renly/features/collaboration/models/cobroke_request_candidate.dart';
import 'package:renly/features/listing/listing_providers.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_draft.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/listing/my_inventory_screen.dart';
import 'package:renly/features/matching/models/match_candidate.dart';
import 'package:renly/features/notifications/notification_providers.dart';
import 'package:renly/features/profile/models/profile.dart';
import 'package:renly/features/profile/profile_providers.dart' hide currentNegotiatorIdProvider;
import 'package:renly/features/requirement/models/requirement.dart';

final _activeListing = Listing(
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
  createdAt: DateTime(2024, 1, 1),
);

final _soldListing = Listing(
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
  createdAt: DateTime(2024, 1, 1),
);

final _inReviewListing = Listing(
  listingId: 'l-3',
  negotiatorId: 'n-1',
  title: 'In Review One',
  description: 'd',
  propertyType: 'house',
  transactionType: 'sale',
  state: 'Johor',
  area: 'Iskandar Puteri',
  price: 700000,
  photoUrls: [],
  status: 'active',
  createdAt: DateTime(2024, 1, 1),
);

final _requirement = Requirement(
  requirementId: 'r-1',
  negotiatorId: 'n-2',
  propertyType: 'house',
  transactionType: 'sale',
  state: 'Johor',
  area: 'Iskandar Puteri',
  budgetMin: 600000,
  budgetMax: 800000,
  photoUrls: [],
  status: 'open',
);

/// A pending inquiry from another negotiator on `_inReviewListing` -- moves
/// that listing out of Active and into Co-Broke in Review per
/// ListingStatusFilter.partition.
final _pendingRequestOnInReviewListing = CobrokeRequestCandidate(
  request: CobrokeRequest(
    requestId: 'req-1',
    matchId: 'm-1',
    initiatorId: 'n-2',
    status: 'pending',
    createdAt: DateTime(2024, 1, 1),
  ),
  match: MatchCandidate(
    matchId: 'm-1',
    score: 90,
    listing: _inReviewListing,
    requirement: _requirement,
    listingOwner: const ListingOwner(fullName: 'Test Owner', renNumber: '12345'),
    requirementOwner: const ListingOwner(fullName: 'Test Requester', renNumber: '54321'),
  ),
);

final _draft = ListingDraft(
  draftId: 'draft-1',
  savedAt: DateTime(2024, 1, 1),
  title: 'Draft Villa',
  description: 'd',
  propertyType: 'house',
  transactionType: 'sale',
  state: 'Johor',
  area: 'Iskandar Puteri',
  price: '650000',
  titleVerified: false,
  exclusiveMandate: false,
);

Widget _wrap(
  GoRouter router, {
  List<Listing>? listings,
  List<CobrokeRequestCandidate>? received,
}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      myListingsProvider.overrideWith((ref, negotiatorId) async => listings ?? [_activeListing, _soldListing]),
      receivedRequestsProvider.overrideWith((ref) async => received ?? const []),
      myProfileProvider.overrideWith(
        (ref) async => const Profile(negotiatorId: 'n-1', fullName: 'Test Agent', verificationStatus: 'verified'),
      ),
      unreadNotificationCountProvider.overrideWith((ref) => 0),
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
    SharedPreferences.setMockInitialValues({});
    rootBundle.clear();
  });

  testWidgets('Active tab shows only active (non co-broke) listings by default', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyInventoryScreen()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      listings: [_activeListing, _soldListing, _inReviewListing],
      received: [_pendingRequestOnInReviewListing],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Active One'), findsOneWidget);
    expect(find.text('Sold One'), findsNothing);
    expect(find.text('In Review One'), findsNothing);
  });

  testWidgets('switching to Co-Broke in Review tab shows only listings with a pending request', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyInventoryScreen()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      listings: [_activeListing, _soldListing, _inReviewListing],
      received: [_pendingRequestOnInReviewListing],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Co-Broke in Review'));
    await tester.pumpAndSettle();

    expect(find.text('In Review One'), findsOneWidget);
    expect(find.text('Active One'), findsNothing);
    expect(find.text('Sold One'), findsNothing);
  });

  testWidgets('switching to Closed / Sold tab shows sold/withdrawn listings', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyInventoryScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, listings: [_activeListing, _soldListing]));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Closed / Sold'));
    await tester.pumpAndSettle();

    expect(find.text('Sold One'), findsOneWidget);
    expect(find.text('Active One'), findsNothing);
  });

  testWidgets('ticker shows the pending co-broke inquiry count and Review navigates to /my-requests',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyInventoryScreen()),
      GoRoute(path: '/my-requests', builder: (context, state) => const Text('my-requests-screen')),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      listings: [_activeListing, _inReviewListing],
      received: [_pendingRequestOnInReviewListing],
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 Co-Broke Inquiries', findRichText: true), findsOneWidget);
    await tester.tap(find.textContaining('Review →'));
    await tester.pumpAndSettle();

    expect(find.text('my-requests-screen'), findsOneWidget);
  });

  testWidgets('Drafts tab shows the empty state when there are no saved drafts', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyInventoryScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Drafts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drafts'));
    await tester.pumpAndSettle();

    expect(find.text('No saved drafts.'), findsOneWidget);
  });

  testWidgets('Drafts tab lists a saved draft and Resume pushes it as /post-listing extra', (tester) async {
    SharedPreferences.setMockInitialValues({
      'listing_drafts': [jsonEncode(_draft.toJson())],
    });

    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyInventoryScreen()),
      GoRoute(
        path: '/post-listing',
        builder: (context, state) => Text('post-listing-${(state.extra as ListingDraft?)?.draftId}'),
      ),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Drafts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drafts'));
    await tester.pumpAndSettle();

    expect(find.text('Draft Villa'), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();

    expect(find.text('post-listing-draft-1'), findsOneWidget);
  });

  testWidgets('tapping Post Property navigates to /post-listing', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyInventoryScreen()),
      GoRoute(path: '/post-listing', builder: (context, state) => const Text('post-listing-screen')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post Property'));
    await tester.pumpAndSettle();

    expect(find.text('post-listing-screen'), findsOneWidget);
  });
}
