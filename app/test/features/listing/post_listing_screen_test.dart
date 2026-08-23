// app/test/features/listing/post_listing_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/listing/listing_providers.dart';
import 'package:renly/features/listing/post_listing_screen.dart';
import 'package:renly/features/subscription/models/subscription_status.dart' as subscription;
import 'package:renly/features/subscription/subscription_providers.dart' as subscription_providers;

Widget _wrap(GoRouter router, {List<Override> overrides = const []}) {
  return ProviderScope(
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
      GoRoute(path: '/', builder: (context, state) => const PostListingScreen()),
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
      GoRoute(path: '/', builder: (context, state) => const PostListingScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    final scrollable = find.byType(SingleChildScrollView);
    await tester.drag(scrollable, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Post Now'));
    await tester.pumpAndSettle();

    expect(find.text('This field is required'), findsWidgets);
  });

  testWidgets('shows active count and disables submit at the free-tier cap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PostListingScreen()),
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

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('does not block submit for a professional-tier negotiator even at 3 active listings', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PostListingScreen()),
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

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
  });
}
