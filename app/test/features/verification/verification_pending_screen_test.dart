import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/verification/verification_pending_screen.dart';

void main() {
  setUpAll(() async {
    // easy_localization persists the selected locale via shared_preferences.
    // The test VM has no platform-channel backend for it, so seed the mock
    // in-memory implementation before initializing EasyLocalization.
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('renders localized verification pending copy', (tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ms')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        child: Builder(
          builder: (context) => MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: const VerificationPendingScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Verification pending'), findsOneWidget);
    expect(
      find.text("Your registration is being checked against the public register. You'll be notified once it's approved."),
      findsOneWidget,
    );
  });
}
