import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/auth/registration_personal_screen.dart';

Widget _wrap(GoRouter router) {
  return ProviderScope(
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

  // rootBundle caches asset-load Futures across FakeAsync test zones; clear it so each test gets a fresh load.
  setUp(() => rootBundle.clear());

  testWidgets('renders all six Step 1 fields', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RegistrationPersonalScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reg_email_field')), findsOneWidget);
    expect(find.byKey(const Key('reg_password_field')), findsOneWidget);
    expect(find.byKey(const Key('reg_confirm_password_field')), findsOneWidget);
    expect(find.byKey(const Key('reg_full_name_field')), findsOneWidget);
    expect(find.byKey(const Key('reg_ic_number_field')), findsOneWidget);
    expect(find.byKey(const Key('reg_phone_number_field')), findsOneWidget);
  });

  testWidgets('mismatched passwords blocks submit with an inline error', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RegistrationPersonalScreen()),
      GoRoute(path: '/register/professional', builder: (context, state) => const Text('step-2')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('reg_email_field')), 'agent@renly.my');
    await tester.enterText(find.byKey(const Key('reg_password_field')), 'password1');
    await tester.enterText(find.byKey(const Key('reg_confirm_password_field')), 'password2');
    await tester.enterText(find.byKey(const Key('reg_full_name_field')), 'Aiman Yusof');
    await tester.enterText(find.byKey(const Key('reg_ic_number_field')), '900101-14-5555');
    await tester.enterText(find.byKey(const Key('reg_phone_number_field')), '012-3456789');
    await tester.pumpAndSettle();
    // Scroll down to ensure button is visible before tapping
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reg_next_step_button')));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(find.text('step-2'), findsNothing);
  });

  testWidgets('invalid IC format blocks submit', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RegistrationPersonalScreen()),
      GoRoute(path: '/register/professional', builder: (context, state) => const Text('step-2')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('reg_email_field')), 'agent@renly.my');
    await tester.enterText(find.byKey(const Key('reg_password_field')), 'password1');
    await tester.enterText(find.byKey(const Key('reg_confirm_password_field')), 'password1');
    await tester.enterText(find.byKey(const Key('reg_full_name_field')), 'Aiman Yusof');
    await tester.enterText(find.byKey(const Key('reg_ic_number_field')), 'not-an-ic');
    await tester.enterText(find.byKey(const Key('reg_phone_number_field')), '012-3456789');
    await tester.pumpAndSettle();
    // Scroll down to ensure button is visible before tapping
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reg_next_step_button')));
    await tester.pumpAndSettle();

    expect(find.text('Enter IC in format 900101-14-5555'), findsOneWidget);
    expect(find.text('step-2'), findsNothing);
  });
}
