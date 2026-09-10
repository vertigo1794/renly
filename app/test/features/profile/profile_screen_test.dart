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
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/core/widgets/negotiator_avatar.dart';
import 'package:renly/features/auth/auth_providers.dart';
import 'package:renly/features/notifications/notification_providers.dart';
import 'package:renly/features/profile/models/profile.dart';
import 'package:renly/features/profile/profile_providers.dart';
import 'package:renly/features/profile/profile_screen.dart';
import 'package:renly/features/ratings/models/rating_candidate.dart';
import 'package:renly/features/ratings/rating_providers.dart' hide currentNegotiatorIdProvider;
import 'package:renly/features/settings/models/notification_preferences.dart';
import 'package:renly/features/settings/settings_providers.dart' hide currentNegotiatorIdProvider;
import 'package:renly/features/settings/settings_repository.dart';

/// Never actually invoked -- see the identical class in
/// post_broadcast_screen_test.dart / post_requirement_screen_test.dart,
/// which this mirrors.
class _FakeSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records the exact arguments of the last updateNotificationPreferences
/// call so tests can assert only notifyMatch was ever sent, never
/// notifyMessage/notifyCobrokeRequest, for the Auto-Match Radar toggle.
class _FakeSettingsRepository extends SettingsRepository {
  _FakeSettingsRepository() : super(_FakeSupabaseClient());

  Map<String, dynamic>? lastCall;

  @override
  Future<void> updateNotificationPreferences({
    required String negotiatorId,
    bool? notifyMatch,
    bool? notifyMessage,
    bool? notifyCobrokeRequest,
  }) async {
    lastCall = {
      'negotiatorId': negotiatorId,
      'notifyMatch': notifyMatch,
      'notifyMessage': notifyMessage,
      'notifyCobrokeRequest': notifyCobrokeRequest,
    };
  }
}

const _fixtureProfile = Profile(
  negotiatorId: 'n-1',
  fullName: 'Aiman Yusof',
  renNumber: '12345',
  agencyName: 'Prestige Property Group',
  territory: 'Petaling Jaya',
  propertySpecialisation: 'Residential',
  verificationStatus: 'approved',
);

Widget _wrap(
  GoRouter router, {
  Profile? profile,
  (int, int, double)? counts,
  List<RatingCandidate>? ratings,
  NotificationPreferences? notificationPreferences,
  bool biometricAvailable = false,
  bool biometricEnabled = false,
  SettingsRepository? settingsRepository,
}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      myProfileProvider.overrideWith((ref) async => profile ?? _fixtureProfile),
      profileCountsProvider.overrideWith((ref) async => counts ?? (5, 3, 125000.0)),
      ratingsForNegotiatorProvider('n-1').overrideWith((ref) async => ratings ?? const []),
      unreadNotificationCountProvider.overrideWithValue(0),
      notificationPreferencesProvider.overrideWith(
        (ref) async =>
            notificationPreferences ??
            const NotificationPreferences(notifyMatch: true, notifyMessage: true, notifyCobrokeRequest: true),
      ),
      biometricAvailableProvider.overrideWith((ref) async => biometricAvailable),
      biometricLoginEnabledProvider.overrideWith((ref) async => biometricEnabled),
      settingsRepositoryProvider.overrideWithValue(settingsRepository ?? _FakeSettingsRepository()),
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
    // Shown twice, deliberately -- the quick status Chip near the name,
    // and the detailed REN License & Verification row in the Account &
    // Compliance card further down. Mirrors the reference mockup's own
    // structure (its own "BOVAEA/LPPEH VERIFIED" pill near the name PLUS
    // a separate "REN License & Verification" row).
    expect(find.text('Verified'), findsNWidgets(2));
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
    expect(find.text('Log Out of Renly'), findsOneWidget);
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

    // Shown twice, deliberately -- see the same reasoning on the
    // "Verified" case above.
    expect(find.text('Verification Pending'), findsNWidgets(2));
  });

  testWidgets('shows "No ratings yet" when the negotiator has no ratings', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, ratings: const []));
    await tester.pumpAndSettle();

    expect(find.text('No ratings yet'), findsOneWidget);
    expect(find.text('TRUST SCORE'), findsOneWidget);
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

  testWidgets('shows a tappable square avatar', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    final avatar = tester.widget<NegotiatorAvatar>(find.byType(NegotiatorAvatar));
    expect(avatar.square, isTrue);
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

  testWidgets('territory field is hidden until Edit Profile is tapped', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Territory'), findsNothing);

    await tester.ensureVisible(find.text('Edit Profile'));
    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Territory'), findsOneWidget);
  });

  testWidgets('shows the real Co-Broke Volume stat', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, counts: (5, 3, 250000.0)));
    await tester.pumpAndSettle();

    expect(find.text('CO-BROKE VOL.'), findsOneWidget);
    expect(find.textContaining('250,000'), findsOneWidget);
  });

  testWidgets('Auto-Match Radar reflects the real notifyMatch preference', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      notificationPreferences: const NotificationPreferences(notifyMatch: false, notifyMessage: true, notifyCobrokeRequest: true),
    ));
    await tester.pumpAndSettle();

    final switchFinder = find.byType(SwitchListTile).first;
    final switchWidget = tester.widget<SwitchListTile>(switchFinder);
    expect(switchWidget.value, isFalse);
  });

  testWidgets('tapping Auto-Match Radar calls updateNotificationPreferences with ONLY notifyMatch set', (tester) async {
    final fakeSettings = _FakeSettingsRepository();
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      settingsRepository: fakeSettings,
      notificationPreferences: const NotificationPreferences(notifyMatch: false, notifyMessage: true, notifyCobrokeRequest: true),
    ));
    await tester.pumpAndSettle();

    final switchFinder = find.byType(SwitchListTile).first;
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(fakeSettings.lastCall, isNotNull);
    expect(fakeSettings.lastCall!['notifyMatch'], isTrue);
    expect(fakeSettings.lastCall!['notifyMessage'], isNull);
    expect(fakeSettings.lastCall!['notifyCobrokeRequest'], isNull);
  });

  testWidgets('shows the real Designated Area when territory is set', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Petaling Jaya'), findsOneWidget);
  });

  testWidgets('shows the real Security & Biometrics status when biometric login is available', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/settings/account', builder: (context, state) => const Text('account screen')),
    ]);

    await tester.pumpWidget(_wrap(router, biometricAvailable: true, biometricEnabled: true));
    await tester.pumpAndSettle();

    expect(find.text('Security & Biometrics'), findsOneWidget);

    await tester.ensureVisible(find.text('Security & Biometrics'));
    await tester.tap(find.text('Security & Biometrics'));
    await tester.pumpAndSettle();
    expect(find.text('account screen'), findsOneWidget);
  });

  testWidgets('hides Security & Biometrics when biometric login is unavailable', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, biometricAvailable: false));
    await tester.pumpAndSettle();

    expect(find.text('Security & Biometrics'), findsNothing);
  });

  // Regression for a bug the final review's own fix round introduced: the
  // header's REN pill (added to match property_detail_screen.dart's own
  // header) leaves this screen with one more AppBar action than that
  // screen has, so the bare wordmark Text (no Flexible/ellipsis) could
  // overflow at narrow widths -- verified empirically: temporarily
  // removing the Flexible wrapper makes this test fail with a RenderFlex
  // overflow exception at 320dp; restoring it (the shipped fix) passes.
  testWidgets('renders the header with no overflow at 320dp', (tester) async {
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
