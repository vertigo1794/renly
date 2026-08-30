// app/test/features/ratings/rate_dialog_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/ratings/rate_dialog.dart';

Widget _wrap({required Widget child}) {
  return ProviderScope(
    child: EasyLocalization(
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
          home: Scaffold(body: child),
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

  testWidgets('defaults to 5 filled stars, tapping the 2nd star selects only the first 2', (tester) async {
    await tester.pumpWidget(_wrap(
      child: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const RateDialog(agreementId: 'agr-1', raterId: 'n-1', ratedId: 'n-2'),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.byIcon(PhosphorIcons.star(PhosphorIconsStyle.bold)),
      findsNWidgets(5),
    );

    await tester.tap(find.byIcon(PhosphorIcons.star(PhosphorIconsStyle.bold)).at(1));
    await tester.pumpAndSettle();

    expect(find.byIcon(PhosphorIcons.star(PhosphorIconsStyle.bold)), findsNWidgets(2));
    expect(find.byIcon(PhosphorIcons.star(PhosphorIconsStyle.regular)), findsNWidgets(3));
  });
}
