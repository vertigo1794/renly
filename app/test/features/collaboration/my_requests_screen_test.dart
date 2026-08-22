// app/test/features/collaboration/my_requests_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/collaboration/cobroke_request_providers.dart';
import 'package:renly/features/collaboration/models/cobroke_request.dart';
import 'package:renly/features/collaboration/models/cobroke_request_candidate.dart';
import 'package:renly/features/collaboration/my_requests_screen.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/matching/models/match_candidate.dart';
import 'package:renly/features/requirement/models/requirement.dart';

const _myListing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'My Listing',
  description: 'd',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  price: 400000,
  photoUrls: [],
  status: 'active',
);

const _theirRequirement = Requirement(
  requirementId: 'r-1',
  negotiatorId: 'n-2',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  budgetMin: 300000,
  budgetMax: 500000,
  photoUrls: [],
  status: 'open',
);

const _owner = ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345');

const _matchCandidate = MatchCandidate(
  matchId: 'm-1',
  score: 90,
  listing: _myListing,
  requirement: _theirRequirement,
  listingOwner: _owner,
  requirementOwner: _owner,
);

final _fixtureReceived = [
  CobrokeRequestCandidate(
    request: CobrokeRequest(
      requestId: 'req-1',
      matchId: 'm-1',
      initiatorId: 'n-2',
      status: 'pending',
      createdAt: DateTime(2026, 8, 23),
    ),
    match: _matchCandidate,
  ),
];

Widget _wrap(GoRouter router, {List<CobrokeRequestCandidate>? received, List<CobrokeRequestCandidate>? sent}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      receivedRequestsProvider.overrideWith((ref) async => received ?? _fixtureReceived),
      sentRequestsProvider.overrideWith((ref) async => sent ?? const []),
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

  testWidgets('Received tab shows a pending request with Accept/Decline', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Aiman Yusof (REN: 12345)'), findsOneWidget);
    expect(find.text('90/100'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
  });

  testWidgets('switching to Sent tab hides Accept/Decline and shows status only', (tester) async {
    final sent = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-2',
          matchId: 'm-2',
          initiatorId: 'n-1',
          status: 'declined',
          createdAt: DateTime(2026, 8, 23),
        ),
        match: _matchCandidate,
      ),
    ];
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, received: [], sent: sent));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sent'));
    await tester.pumpAndSettle();

    expect(find.text('Declined'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Decline'), findsNothing);
  });

  testWidgets('renders empty state on Received tab when no requests', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, received: [], sent: []));
    await tester.pumpAndSettle();

    expect(find.text('No requests yet'), findsOneWidget);
  });

  testWidgets('accepted request shows a Chat button, pending does not', (tester) async {
    final pendingRouter = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    // _fixtureReceived (the default when `received` is omitted) is a
    // 'pending' request -- confirm no Chat button renders for it before
    // testing the accepted case below.
    await tester.pumpWidget(_wrap(pendingRouter));
    await tester.pumpAndSettle();

    expect(find.text('Chat'), findsNothing);

    // Force a full unmount before the second full-tree pump below: it swaps
    // in a different GoRouter instance at the same widget-tree position,
    // and without an intervening unmount MaterialApp.router would try to
    // hot-swap a live Router's delegate instead of rebuilding from scratch.
    await tester.pumpWidget(const SizedBox.shrink());

    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-3',
          matchId: 'm-3',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
      GoRoute(
        path: '/messages/:requestId',
        builder: (context, state) => Scaffold(body: Text('chat for ${state.pathParameters['requestId']}')),
      ),
    ]);

    await tester.pumpWidget(_wrap(router, received: accepted));
    await tester.pumpAndSettle();

    expect(find.text('Chat'), findsOneWidget);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    expect(find.text('chat for req-3'), findsOneWidget);
  });
}
