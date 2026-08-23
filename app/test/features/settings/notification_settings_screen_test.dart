import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/settings/models/notification_preferences.dart';
import 'package:renly/features/settings/notification_settings_screen.dart';
import 'package:renly/features/settings/settings_providers.dart';

Widget _wrap(GoRouter router, {NotificationPreferences? prefs, Object? error}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      if (error != null)
        notificationPreferencesProvider.overrideWith((ref) async => throw error)
      else
        notificationPreferencesProvider.overrideWith(
          (ref) async =>
              prefs ??
              const NotificationPreferences(notifyMatch: true, notifyMessage: false, notifyCobrokeRequest: true),
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

  testWidgets('renders three toggles with the provider-supplied initial state', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const NotificationSettingsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('New matches'), findsOneWidget);
    expect(find.text('New messages'), findsOneWidget);
    expect(find.text('New co-broke requests'), findsOneWidget);

    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
    expect(switches[0].value, isTrue);
    expect(switches[1].value, isFalse);
    expect(switches[2].value, isTrue);
  });

  testWidgets('shows visible error text on load failure, not a blank screen', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const NotificationSettingsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, error: StateError('boom')));
    await tester.pumpAndSettle();

    expect(find.text('listing_error_generic'.tr()), findsOneWidget);
  });
}
