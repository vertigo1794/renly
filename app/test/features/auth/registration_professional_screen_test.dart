import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/auth/registration_professional_screen.dart';

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

  setUp(() {
    rootBundle.clear();
  });

  testWidgets('renders REN number, agency name, and tag photo upload fields', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const RegistrationProfessionalScreen(negotiatorId: 'test-id'),
      ),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reg_ren_number_field')), findsOneWidget);
    expect(find.byKey(const Key('reg_agency_name_field')), findsOneWidget);
    expect(find.text('Choose File'), findsOneWidget);
  });

  testWidgets('submitting with empty required fields shows validation errors', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const RegistrationProfessionalScreen(negotiatorId: 'test-id'),
      ),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    // Scroll down to ensure the button is on-screen before tapping -- the
    // added progress bar + restyled upload card made the form taller than
    // the test viewport, same reasoning as registration_personal_screen_test.dart.
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Complete Registration'));
    await tester.pumpAndSettle();

    expect(find.text('This field is required'), findsWidgets);
  });
}
