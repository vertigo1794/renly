// app/test/features/profile/profile_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/profile/models/profile.dart';
import 'package:renly/features/profile/profile_providers.dart';
import 'package:renly/features/profile/profile_screen.dart';

const _fixtureProfile = Profile(
  negotiatorId: 'n-1',
  fullName: 'Aiman Yusof',
  renNumber: '12345',
  agencyName: 'Prestige Property Group',
  territory: 'Petaling Jaya',
  propertySpecialisation: 'Residential',
  verificationStatus: 'approved',
);

Widget _wrap(GoRouter router, {Profile? profile, (int, int)? counts}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      myProfileProvider.overrideWith((ref) async => profile ?? _fixtureProfile),
      profileCountsProvider.overrideWith((ref) async => counts ?? (5, 3)),
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
}
