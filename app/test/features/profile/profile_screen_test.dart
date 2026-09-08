// app/test/features/profile/profile_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/core/widgets/negotiator_avatar.dart';
import 'package:renly/features/notifications/notification_providers.dart';
import 'package:renly/features/profile/models/profile.dart';
import 'package:renly/features/profile/profile_providers.dart';
import 'package:renly/features/profile/profile_screen.dart';
import 'package:renly/features/ratings/models/rating_candidate.dart';
import 'package:renly/features/ratings/rating_providers.dart' hide currentNegotiatorIdProvider;

const _fixtureProfile = Profile(
  negotiatorId: 'n-1',
  fullName: 'Aiman Yusof',
  renNumber: '12345',
  agencyName: 'Prestige Property Group',
  territory: 'Petaling Jaya',
  propertySpecialisation: 'Residential',
  verificationStatus: 'approved',
);

Widget _wrap(GoRouter router, {Profile? profile, (int, int)? counts, List<RatingCandidate>? ratings}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      myProfileProvider.overrideWith((ref) async => profile ?? _fixtureProfile),
      profileCountsProvider.overrideWith((ref) async => counts ?? (5, 3)),
      ratingsForNegotiatorProvider('n-1').overrideWith((ref) async => ratings ?? const []),
      unreadNotificationCountProvider.overrideWithValue(0),
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

  testWidgets('renders profile fields and counts', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Aiman Yusof'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Registration Number: 12345'), findsOneWidget);
    expect(find.text('Agency: Prestige Property Group'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('language switcher and sign out button are present', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('English'), findsOneWidget);
    expect(find.text('Bahasa Melayu'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
  });

  testWidgets('shows pending status label for a pending profile', (tester) async {
    const pendingProfile = Profile(
      negotiatorId: 'n-1',
      fullName: 'Aiman Yusof',
      verificationStatus: 'pending',
    );
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, profile: pendingProfile));
    await tester.pumpAndSettle();

    expect(find.text('Verification Pending'), findsOneWidget);
  });

  testWidgets('shows "No ratings yet" when the negotiator has no ratings', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, ratings: const []));
    await tester.pumpAndSettle();

    expect(find.text('No ratings yet'), findsOneWidget);
    expect(find.text('Trust Score'), findsOneWidget);
  });

  testWidgets('renders the 4 settings rows and navigates to each on tap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/settings/notification', builder: (context, state) => const Text('notification screen')),
      GoRoute(path: '/settings/account', builder: (context, state) => const Text('account screen')),
      GoRoute(path: '/settings/privacy', builder: (context, state) => const Text('privacy screen')),
      GoRoute(path: '/settings/help', builder: (context, state) => const Text('help screen')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Notification'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Help'), findsOneWidget);

    await tester.ensureVisible(find.text('Notification'));
    await tester.tap(find.text('Notification'));
    await tester.pumpAndSettle();
    expect(find.text('notification screen'), findsOneWidget);
  });

  testWidgets('renders the Subscription row and navigates to it on tap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/settings/subscription', builder: (context, state) => const Text('subscription screen')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Subscription'), findsOneWidget);

    await tester.ensureVisible(find.text('Subscription'));
    await tester.tap(find.text('Subscription'));
    await tester.pumpAndSettle();
    expect(find.text('subscription screen'), findsOneWidget);
  });

  testWidgets('shows a tappable avatar with the upload hint', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byType(NegotiatorAvatar), findsOneWidget);
    expect(find.text('profile_avatar_upload_hint'.tr()), findsOneWidget);
  });

  testWidgets('shows the renly wordmark and a share/bell header', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('renly'), findsOneWidget);
    expect(find.byIcon(PhosphorIcons.shareNetwork(PhosphorIconsStyle.bold)), findsOneWidget);
    expect(find.byIcon(PhosphorIcons.bellSimple(PhosphorIconsStyle.bold)), findsOneWidget);
  });
}
