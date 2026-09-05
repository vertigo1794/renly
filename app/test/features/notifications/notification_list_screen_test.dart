import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/notifications/models/app_notification.dart';
import 'package:renly/features/notifications/notification_list_screen.dart';
import 'package:renly/features/notifications/notification_providers.dart';

final _unread = AppNotification(
  notificationId: 'n-1',
  category: 'message',
  title: 'New message',
  body: 'You have a new message',
  deepLinkData: const {'request_id': 'req-1'},
  readAt: null,
  createdAt: DateTime(2026, 9, 5, 10, 0),
);

final _read = AppNotification(
  notificationId: 'n-2',
  category: 'cobroke_request',
  title: 'New request',
  body: 'You have a new co-broke request',
  deepLinkData: const {},
  readAt: DateTime(2026, 9, 5, 9, 0),
  createdAt: DateTime(2026, 9, 5, 9, 0),
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  testWidgets('renders notifications and navigates to the deep-linked route on tap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const NotificationListScreen()),
      GoRoute(
        path: '/messages/:requestId',
        builder: (context, state) => Text('chat-${state.pathParameters['requestId']}'),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [notificationsProvider.overrideWith((ref) async => [_unread, _read])],
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

    expect(find.text('New message'), findsOneWidget);
    expect(find.text('New request'), findsOneWidget);

    await tester.tap(find.text('New message'));
    await tester.pumpAndSettle();

    expect(find.text('chat-req-1'), findsOneWidget);
  });
}
