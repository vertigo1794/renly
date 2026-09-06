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
import 'package:renly/features/notifications/notification_providers.dart';
import 'package:renly/features/profile/models/profile.dart';
import 'package:renly/features/profile/profile_providers.dart' hide currentNegotiatorIdProvider;
import 'package:renly/features/collaboration/cobroke_request_providers.dart' hide currentNegotiatorIdProvider;

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
      ],
    );

    expect(find.textContaining('REN'), findsNothing);
  });
}
