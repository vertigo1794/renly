import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/core/widgets/brutalist_button.dart';
import 'package:renly/core/widgets/negotiator_avatar.dart';
import 'package:renly/features/listing/models/listing_owner.dart';
import 'package:renly/features/requirement/models/requirement.dart';
import 'package:renly/features/requirement/requirement_detail_screen.dart';
import 'package:renly/features/requirement/requirement_providers.dart';
import 'package:renly/features/subscription/models/subscription_status.dart' as subscription;
import 'package:renly/features/subscription/subscription_providers.dart' as subscription_providers;

const _fixtureRequirement = Requirement(
  requirementId: 'r-1',
  negotiatorId: 'n-1',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  budgetMin: 300000,
  budgetMax: 500000,
  bedrooms: 3,
  photoUrls: [],
  status: 'open',
);

const _withdrawnRequirementOwnedByN1 = Requirement(
  requirementId: 'r-1',
  negotiatorId: 'n-1',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  budgetMin: 300000,
  budgetMax: 500000,
  bedrooms: 3,
  photoUrls: [],
  status: 'withdrawn',
);

const _fixtureOwner = ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345');

Widget _wrap(GoRouter router, {String currentNegotiatorId = 'n-2', Requirement? requirement, List<Override> extraOverrides = const []}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue(currentNegotiatorId),
      requirementDetailProvider.overrideWith((ref, requirementId) async => requirement ?? _fixtureRequirement),
      requirementOwnerProvider.overrideWith((ref, negotiatorId) async => _fixtureOwner),
      ...extraOverrides,
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

  testWidgets('renders budget range, criteria, location, and owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementDetailScreen(requirementId: 'r-1')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('RM 300,000 - RM 500,000'), findsOneWidget);
    expect(find.text('Apartment · Sale'), findsOneWidget);
    expect(find.text('Petaling Jaya, Selangor'), findsOneWidget);
    expect(find.text('Aiman Yusof'), findsOneWidget);
    expect(find.text('REN: 12345'), findsOneWidget);
  });

  testWidgets('shows status-change actions when viewer is the owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementDetailScreen(requirementId: 'r-1')),
    ]);

    await tester.pumpWidget(_wrap(router, currentNegotiatorId: 'n-1'));
    await tester.pumpAndSettle();

    expect(find.text('Mark as Fulfilled'), findsOneWidget);
  });

  testWidgets('hides status-change actions when viewer is not the owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementDetailScreen(requirementId: 'r-1')),
    ]);

    await tester.pumpWidget(_wrap(router, currentNegotiatorId: 'n-2'));
    await tester.pumpAndSettle();

    expect(find.text('Mark as Fulfilled'), findsNothing);
  });

  testWidgets('disables the reactivate button at the free-tier active-requirement cap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementDetailScreen(requirementId: 'r-1')),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      currentNegotiatorId: 'n-1',
      requirement: _withdrawnRequirementOwnedByN1,
      extraOverrides: [
        activeRequirementCountProvider('n-1').overrideWith((ref) async => 3),
        subscription_providers.subscriptionStatusProvider.overrideWith(
          (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'free')),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text("You've reached the Free plan's limit of 3 active requirements. Upgrade to Professional for unlimited requirements."), findsOneWidget);

    final reactivateButton = tester.widget<BrutalistButton>(
      find.widgetWithText(BrutalistButton, 'requirement_reactivate'.tr()),
    );
    expect(reactivateButton.onPressed, isNull);
  });

  testWidgets('keeps the reactivate button enabled for a free-tier owner under the cap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementDetailScreen(requirementId: 'r-1')),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      currentNegotiatorId: 'n-1',
      requirement: _withdrawnRequirementOwnedByN1,
      extraOverrides: [
        activeRequirementCountProvider('n-1').overrideWith((ref) async => 2),
        subscription_providers.subscriptionStatusProvider.overrideWith(
          (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'free')),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text("You've reached the Free plan's limit of 3 active requirements. Upgrade to Professional for unlimited requirements."), findsNothing);

    final reactivateButton = tester.widget<BrutalistButton>(
      find.widgetWithText(BrutalistButton, 'requirement_reactivate'.tr()),
    );
    expect(reactivateButton.onPressed, isNotNull);
  });

  testWidgets('renders a NegotiatorAvatar for the requirement owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementDetailScreen(requirementId: 'r-1')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byType(NegotiatorAvatar), findsOneWidget);
  });
}
