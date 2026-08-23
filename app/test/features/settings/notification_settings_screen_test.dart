import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/settings/models/identity_info.dart';
import 'package:renly/features/settings/models/notification_preferences.dart';
import 'package:renly/features/settings/notification_settings_screen.dart';
import 'package:renly/features/settings/settings_providers.dart';
import 'package:renly/features/settings/settings_repository.dart';

/// Records every call to updateNotificationPreferences so a test can assert
/// on exactly what payload a tap produced -- in particular, that only the
/// single field the user touched is non-null, not all three (the bug this
/// regression test exists to catch: see settings_repository.dart and
/// NotificationSettingsScreen._toggle).
class _RecordingSettingsRepository implements SettingsRepository {
  final calls = <Map<String, bool?>>[];

  @override
  Future<void> updateNotificationPreferences({
    required String negotiatorId,
    bool? notifyMatch,
    bool? notifyMessage,
    bool? notifyCobrokeRequest,
  }) async {
    calls.add({
      'notifyMatch': notifyMatch,
      'notifyMessage': notifyMessage,
      'notifyCobrokeRequest': notifyCobrokeRequest,
    });
  }

  @override
  Future<NotificationPreferences> fetchNotificationPreferences(String negotiatorId) =>
      throw UnimplementedError();

  @override
  Future<IdentityInfo> fetchIdentityInfo(String negotiatorId) => throw UnimplementedError();

  @override
  Future<void> updatePassword(String newPassword) => throw UnimplementedError();
}

Widget _wrap(GoRouter router, {NotificationPreferences? prefs, Object? error, SettingsRepository? repository}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      if (repository != null) settingsRepositoryProvider.overrideWithValue(repository),
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

  testWidgets('toggling one switch writes only that field, not a full-row snapshot', (tester) async {
    final fakeRepo = _RecordingSettingsRepository();
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const NotificationSettingsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, repository: fakeRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(fakeRepo.calls, hasLength(1));
    final payload = fakeRepo.calls.single;
    final nonNullEntries = payload.entries.where((entry) => entry.value != null);
    expect(nonNullEntries, hasLength(1));
    expect(payload['notifyMatch'], isNotNull);
    expect(payload['notifyMessage'], isNull);
    expect(payload['notifyCobrokeRequest'], isNull);
  });
}
