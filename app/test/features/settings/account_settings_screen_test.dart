import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/auth/auth_providers.dart';
import 'package:renly/features/settings/account_settings_screen.dart';
import 'package:renly/features/settings/models/identity_info.dart';
import 'package:renly/features/settings/settings_providers.dart';

Widget _wrap(GoRouter router, {IdentityInfo? info, List<Override> extraOverrides = const []}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      identityInfoProvider.overrideWith(
        (ref) async =>
            info ?? const IdentityInfo(icNumber: '900101-14-1234', phoneNumber: '012-3456789', renNumber: '12345'),
      ),
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

  testWidgets('renders identity info from the provider', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const AccountSettingsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('IC Number: 900101-14-1234'), findsOneWidget);
    expect(find.text('Phone Number: 012-3456789'), findsOneWidget);
    expect(find.text('Registration Number: 12345'), findsOneWidget);
  });

  testWidgets('shows a fallback dash for null identity fields', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const AccountSettingsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, info: const IdentityInfo()));
    await tester.pumpAndSettle();

    expect(find.text('IC Number: -'), findsOneWidget);
    expect(find.text('Phone Number: -'), findsOneWidget);
    expect(find.text('Registration Number: -'), findsOneWidget);
  });

  testWidgets('blocks submit and shows an error when passwords do not match', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const AccountSettingsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'New Password'), 'password123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm New Password'), 'different123');
    await tester.tap(find.text('Update Password'));
    await tester.pumpAndSettle();

    expect(find.text('validation_password_mismatch'.tr()), findsOneWidget);
  });

  testWidgets('biometric toggle hidden when unavailable', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const AccountSettingsScreen()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      extraOverrides: [biometricAvailableProvider.overrideWith((ref) async => false)],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Enable Biometric Login'), findsNothing);
  });

  testWidgets('biometric toggle shown and reflects enabled state when available', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const AccountSettingsScreen()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      extraOverrides: [
        biometricAvailableProvider.overrideWith((ref) async => true),
        biometricLoginEnabledProvider.overrideWith((ref) async => true),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Enable Biometric Login'), findsOneWidget);
    final switchTile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(switchTile.value, isTrue);
  });
}
