// app/test/features/collaboration/chat_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/collaboration/chat_screen.dart';
import 'package:renly/features/collaboration/message_providers.dart';
import 'package:renly/features/collaboration/models/message.dart';

final _fixtureMessages = [
  Message(
    messageId: 'msg-1',
    requestId: 'req-1',
    senderId: 'n-2',
    body: 'Hi, interested to co-broke.',
    sentAt: DateTime(2026, 8, 24, 10, 0),
  ),
  Message(
    messageId: 'msg-2',
    requestId: 'req-1',
    senderId: 'n-1',
    body: 'Sure, let us discuss.',
    sentAt: DateTime(2026, 8, 24, 10, 1),
  ),
];

Widget _wrap(GoRouter router, {List<Message>? messages}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      messagesStreamProvider('req-1').overrideWith((ref) => Stream.value(messages ?? _fixtureMessages)),
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

  testWidgets('renders messages from the fixed stream', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ChatScreen(requestId: 'req-1')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Hi, interested to co-broke.'), findsOneWidget);
    expect(find.text('Sure, let us discuss.'), findsOneWidget);
  });

  testWidgets('renders empty state when there are no messages', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ChatScreen(requestId: 'req-1')),
    ]);

    await tester.pumpWidget(_wrap(router, messages: []));
    await tester.pumpAndSettle();

    expect(find.text('No messages yet. Say hello!'), findsOneWidget);
  });

  testWidgets('send button is present with input hint', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ChatScreen(requestId: 'req-1')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Send'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Type a message...'), findsOneWidget);
  });
}
