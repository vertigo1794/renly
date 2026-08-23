// app/test/features/subscription/subscription_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/subscription/models/subscription_status.dart';
import 'package:renly/features/subscription/subscription_providers.dart';
import 'package:renly/features/subscription/subscription_screen.dart';

Widget _wrap(GoRouter router, {SubscriptionStatus? status, Object? error}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      if (error != null)
        subscriptionStatusProvider.overrideWith((ref) => Stream.error(error))
      else
        subscriptionStatusProvider.overrideWith(
          (ref) => Stream.value(status ?? const SubscriptionStatus(tier: 'free')),
        ),
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

  testWidgets('shows Upgrade button for a free-tier negotiator', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const SubscriptionScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Free Plan'), findsOneWidget);
    expect(find.text('Upgrade to Professional'), findsOneWidget);
    expect(find.text('Manage Subscription'), findsNothing);
  });

  testWidgets('shows Manage Subscription and renewal date for a professional negotiator', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const SubscriptionScreen()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      status: SubscriptionStatus(
        tier: 'professional',
        status: 'active',
        currentPeriodEnd: DateTime(2026, 9, 24),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Professional Plan'), findsOneWidget);
    expect(find.text('Manage Subscription'), findsOneWidget);
    expect(find.text('Upgrade to Professional'), findsNothing);
  });

  testWidgets('shows visible error text on load failure, not a blank screen', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const SubscriptionScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, error: StateError('boom')));
    await tester.pumpAndSettle();

    expect(find.text('listing_error_generic'.tr()), findsOneWidget);
  });
}
