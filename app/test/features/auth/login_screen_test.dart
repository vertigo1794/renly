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
import 'package:renly/core/widgets/brutalist_button.dart';
import 'package:renly/features/auth/auth_providers.dart';
import 'package:renly/features/auth/login_screen.dart';

Widget _wrap(GoRouter router) {
  return ProviderScope(
    overrides: [
      biometricLoginEnabledProvider.overrideWith((ref) async => false),
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

  testWidgets('renders email and password fields', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_email_field')), findsOneWidget);
    expect(find.byKey(const Key('login_password_field')), findsOneWidget);
  });

  testWidgets('submitting with empty fields shows validation errors and does not submit', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BrutalistButton, 'Log In'));
    await tester.pumpAndSettle();

    expect(find.text('This field is required'), findsWidgets);
  });

  testWidgets('password visibility toggle switches obscureText', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    TextField passwordField() => tester.widget<TextField>(
          find.descendant(of: find.byKey(const Key('login_password_field')), matching: find.byType(TextField)),
        );

    expect(passwordField().obscureText, isTrue);
    await tester.tap(find.byIcon(PhosphorIcons.eye(PhosphorIconsStyle.bold)));
    await tester.pumpAndSettle();
    expect(passwordField().obscureText, isFalse);
  });

  testWidgets('biometric button is hidden when biometricLoginEnabledProvider resolves false', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Biometric / REN'), findsNothing);
  });

  testWidgets('biometric button is shown when biometricLoginEnabledProvider resolves true', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [biometricLoginEnabledProvider.overrideWith((ref) async => true)],
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

    expect(find.text('Biometric / REN'), findsOneWidget);
  });

  testWidgets('forgot password link opens dialog with generic success message', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forgot_password_email_field')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('forgot_password_email_field')), 'agent@renly.my');
    await tester.tap(find.text('Send Link'));
    await tester.pumpAndSettle();

    expect(find.text('Check your email for a reset link.'), findsOneWidget);
  });
}
