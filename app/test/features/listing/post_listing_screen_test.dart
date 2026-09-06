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
import 'package:renly/features/listing/models/listing.dart';
import 'package:renly/features/listing/post_listing_screen.dart';
import 'package:renly/core/widgets/brutalist_button.dart';
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

    // find.byType(BrutalistButton) alone now matches 2 widgets (Post Now +
    // Save as Draft), so the primary submit button must be looked up by its
    // own label.
    final button = tester.widget<BrutalistButton>(find.widgetWithText(BrutalistButton, 'Post Now'));
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
        builder: (context, state) => const PostListingScreen(editListingId: 'l-1'),
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
}
