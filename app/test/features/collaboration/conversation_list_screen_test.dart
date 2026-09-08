// app/test/features/collaboration/conversation_list_screen_test.dart
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
import 'package:renly/features/collaboration/cobroke_request_providers.dart';
import 'package:renly/features/collaboration/conversation_list_screen.dart';
import 'package:renly/features/collaboration/models/cobroke_request.dart';
import 'package:renly/features/collaboration/models/cobroke_request_candidate.dart';
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/matching/models/match_candidate.dart';
import 'package:renly/features/requirement/models/requirement.dart';

final _listing = Listing(
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

const _requirement = Requirement(
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

const _owner = ListingOwner(fullName: 'Owner', renNumber: '12345');

final _match = MatchCandidate(
  matchId: 'm-1',
  score: 90,
  listing: _listing,
  requirement: _requirement,
  listingOwner: _owner,
  requirementOwner: _owner,
);

CobrokeRequestCandidate _candidate(String requestId, String status) {
  return CobrokeRequestCandidate(
    request: CobrokeRequest(
      requestId: requestId,
      matchId: 'm-1',
      initiatorId: 'n-2',
      status: status,
      createdAt: DateTime(2026, 9, 5),
    ),
    match: _match,
  );
}

const _onlineOwner = ListingOwner(fullName: 'Owner', renNumber: '12345', isOnline: true);

final _onlineMatch = MatchCandidate(
  matchId: 'm-1',
  score: 90,
  listing: _listing,
  requirement: _requirement,
  listingOwner: _onlineOwner,
  requirementOwner: _onlineOwner,
);

Widget _wrap(GoRouter router, {List<CobrokeRequestCandidate>? received}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      receivedRequestsProvider.overrideWith((ref) async => received ?? [_candidate('req-1', 'accepted')]),
      sentRequestsProvider.overrideWith((ref) async => const []),
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

  test('keeps only accepted requests from received+sent, deduplicated by requestId', () {
    final received = [_candidate('req-1', 'accepted'), _candidate('req-2', 'pending')];
    final sent = [_candidate('req-3', 'accepted'), _candidate('req-1', 'accepted')];

    final result = mergeAcceptedConversations(received, sent);

    expect(result.map((c) => c.request.requestId).toSet(), {'req-1', 'req-3'});
  });

  test('returns an empty list when nothing is accepted', () {
    final received = [_candidate('req-1', 'pending')];
    final sent = [_candidate('req-2', 'declined')];

    expect(mergeAcceptedConversations(received, sent), isEmpty);
  });

  testWidgets('shows a NegotiatorAvatar for the counterparty', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ConversationListScreen()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      received: [
        CobrokeRequestCandidate(
          request: CobrokeRequest(
            requestId: 'req-1',
            matchId: 'm-1',
            initiatorId: 'n-2',
            status: 'accepted',
            createdAt: DateTime(2026, 9, 5),
          ),
          match: _onlineMatch,
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.byType(NegotiatorAvatar), findsWidgets);
  });
}
