import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/ratings/models/rating.dart';
import 'package:renly/features/ratings/models/rating_candidate.dart';
import 'package:renly/features/ratings/rating_providers.dart';
import 'package:renly/features/ratings/reviews_screen.dart';

final _fixtureCandidates = [
  RatingCandidate(
    rating: Rating(
      ratingId: 'rat-1',
      agreementId: 'agr-1',
      raterId: 'n-2',
      ratedId: 'n-1',
      stars: 5,
      reviewText: 'Excellent to work with.',
      createdAt: DateTime(2026, 8, 24),
    ),
    rater: const ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345'),
  ),
];

Widget _wrap(GoRouter router, {List<RatingCandidate>? candidates}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      ratingsForNegotiatorProvider('n-1').overrideWith((ref) async => candidates ?? _fixtureCandidates),
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

  testWidgets('renders reviews from the fixed provider override', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ReviewsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Aiman Yusof'), findsOneWidget);
    expect(find.text('5 / 5'), findsOneWidget);
    expect(find.text('Excellent to work with.'), findsOneWidget);
  });

  testWidgets('renders empty state when there are no reviews', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ReviewsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, candidates: []));
    await tester.pumpAndSettle();

    expect(find.text('No reviews yet'), findsOneWidget);
  });
}
