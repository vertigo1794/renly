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
import 'package:renly/core/widgets/negotiator_avatar.dart';
import 'package:renly/features/collaboration/agreement_providers.dart' hide currentNegotiatorIdProvider;
import 'package:renly/features/collaboration/cobroke_request_providers.dart';
import 'package:renly/features/collaboration/models/agreement.dart';
import 'package:renly/features/collaboration/models/cobroke_request.dart';
import 'package:renly/features/collaboration/models/cobroke_request_candidate.dart';
import 'package:renly/features/collaboration/my_requests_screen.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/matching/models/match_candidate.dart';
import 'package:renly/features/ratings/models/rating.dart';
import 'package:renly/features/ratings/rating_providers.dart' hide currentNegotiatorIdProvider;
import 'package:renly/features/requirement/models/requirement.dart';

final _myListing = Listing(
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
  createdAt: DateTime(2024, 1, 1),
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

final _matchCandidate = MatchCandidate(
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

Widget _wrap(
  GoRouter router, {
  List<CobrokeRequestCandidate>? received,
  List<CobrokeRequestCandidate>? sent,
  String? agreementRequestId,
  Agreement? agreement,
  String? ratingAgreementId,
  Rating? rating,
}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      receivedRequestsProvider.overrideWith((ref) async => received ?? _fixtureReceived),
      sentRequestsProvider.overrideWith((ref) async => sent ?? const []),
      if (agreementRequestId != null)
        agreementForRequestProvider(agreementRequestId).overrideWith((ref) async => agreement),
      if (ratingAgreementId != null)
        myRatingForAgreementProvider(ratingAgreementId).overrideWith((ref) async => rating),
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

    await tester.pumpWidget(_wrap(router, received: accepted, agreementRequestId: 'req-3', agreement: null));
    await tester.pumpAndSettle();

    expect(find.text('Chat'), findsOneWidget);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    expect(find.text('chat for req-3'), findsOneWidget);
  });

  testWidgets('shows Propose Agreement button when accepted request has no agreement', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-4',
          matchId: 'm-4',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, received: accepted, agreementRequestId: 'req-4'));
    await tester.pumpAndSettle();

    expect(find.text('Propose Agreement'), findsOneWidget);
  });

  testWidgets('shows split and Accept/Decline when viewer is the agreement recipient', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-5',
          matchId: 'm-5',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final agreement = Agreement(
      agreementId: 'agr-1',
      requestId: 'req-5',
      initiatorId: 'n-2',
      splitInitiator: 60,
      splitCounterparty: 40,
      status: 'pending',
      createdAt: DateTime(2026, 8, 24),
    );
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, received: accepted, agreementRequestId: 'req-5', agreement: agreement));
    await tester.pumpAndSettle();

    expect(find.text('60% / 40%'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
  });

  testWidgets('shows waiting-for-response label when viewer is the agreement initiator', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-6',
          matchId: 'm-6',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final agreement = Agreement(
      agreementId: 'agr-2',
      requestId: 'req-6',
      initiatorId: 'n-1',
      splitInitiator: 50,
      splitCounterparty: 50,
      status: 'pending',
      createdAt: DateTime(2026, 8, 24),
    );
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, received: accepted, agreementRequestId: 'req-6', agreement: agreement));
    await tester.pumpAndSettle();

    expect(find.text('Waiting for response'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
  });

  testWidgets('shows final split and accepted date when agreement is accepted', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-7',
          matchId: 'm-7',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final agreement = Agreement(
      agreementId: 'agr-3',
      requestId: 'req-7',
      initiatorId: 'n-2',
      splitInitiator: 70,
      splitCounterparty: 30,
      status: 'accepted',
      acceptedAt: DateTime(2026, 8, 25),
      createdAt: DateTime(2026, 8, 24),
    );
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, received: accepted, agreementRequestId: 'req-7', agreement: agreement));
    await tester.pumpAndSettle();

    expect(find.text('70% / 30%'), findsOneWidget);
    expect(find.text('Accepted on 25/8/2026'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Decline'), findsNothing);
    expect(find.text('Propose Agreement'), findsNothing);
  });

  testWidgets('propose dialog validates that shares sum to 100', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-8',
          matchId: 'm-8',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, received: accepted, agreementRequestId: 'req-8'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Propose Agreement'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '60');
    await tester.enterText(find.byType(TextFormField).at(1), '30');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Shares must add up to 100'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), '33.33');
    await tester.enterText(find.byType(TextFormField).at(1), '66.67');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Shares must add up to 100'), findsNothing);
  });

  testWidgets('shows Propose Agreement button again when the latest agreement was declined', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-9',
          matchId: 'm-9',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final declinedAgreement = Agreement(
      agreementId: 'agr-4',
      requestId: 'req-9',
      initiatorId: 'n-2',
      splitInitiator: 60,
      splitCounterparty: 40,
      status: 'declined',
      createdAt: DateTime(2026, 8, 24),
    );
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(
      _wrap(router, received: accepted, agreementRequestId: 'req-9', agreement: declinedAgreement),
    );
    await tester.pumpAndSettle();

    expect(find.text('Propose Agreement'), findsOneWidget);
  });

  testWidgets('shows Rate button when accepted agreement has no rating yet', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-10',
          matchId: 'm-10',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final agreement = Agreement(
      agreementId: 'agr-5',
      requestId: 'req-10',
      initiatorId: 'n-2',
      splitInitiator: 50,
      splitCounterparty: 50,
      status: 'accepted',
      acceptedAt: DateTime(2026, 8, 24),
      createdAt: DateTime(2026, 8, 24),
    );
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      received: accepted,
      agreementRequestId: 'req-10',
      agreement: agreement,
      ratingAgreementId: 'agr-5',
      rating: null,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Rate'), findsOneWidget);
  });

  testWidgets('shows Edit rating button within the 24-hour window', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-11',
          matchId: 'm-11',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final agreement = Agreement(
      agreementId: 'agr-6',
      requestId: 'req-11',
      initiatorId: 'n-2',
      splitInitiator: 50,
      splitCounterparty: 50,
      status: 'accepted',
      acceptedAt: DateTime(2026, 8, 24),
      createdAt: DateTime(2026, 8, 24),
    );
    final recentRating = Rating(
      ratingId: 'rat-10',
      agreementId: 'agr-6',
      raterId: 'n-1',
      ratedId: 'n-2',
      stars: 4,
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    );
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      received: accepted,
      agreementRequestId: 'req-11',
      agreement: agreement,
      ratingAgreementId: 'agr-6',
      rating: recentRating,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Edit rating'), findsOneWidget);
    expect(find.text('Rate'), findsNothing);
  });

  testWidgets('shows read-only "you rated" text past the 24-hour window', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-12',
          matchId: 'm-12',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final agreement = Agreement(
      agreementId: 'agr-7',
      requestId: 'req-12',
      initiatorId: 'n-2',
      splitInitiator: 50,
      splitCounterparty: 50,
      status: 'accepted',
      acceptedAt: DateTime(2026, 8, 24),
      createdAt: DateTime(2026, 8, 24),
    );
    final oldRating = Rating(
      ratingId: 'rat-11',
      agreementId: 'agr-7',
      raterId: 'n-1',
      ratedId: 'n-2',
      stars: 2,
      createdAt: DateTime.now().subtract(const Duration(hours: 25)),
    );
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      received: accepted,
      agreementRequestId: 'req-12',
      agreement: agreement,
      ratingAgreementId: 'agr-7',
      rating: oldRating,
    ));
    await tester.pumpAndSettle();

    expect(find.text('You rated: 2'), findsOneWidget);
    expect(find.text('Rate'), findsNothing);
    expect(find.text('Edit rating'), findsNothing);
  });

  testWidgets('renders a NegotiatorAvatar for the counterparty owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byType(NegotiatorAvatar), findsOneWidget);
  });
}
