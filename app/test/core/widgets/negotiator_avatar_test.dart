// app/test/core/widgets/negotiator_avatar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/core/widgets/negotiator_avatar.dart';

void main() {
  group('NegotiatorAvatar', () {
    testWidgets('renders the initials fallback when avatarUrl is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NegotiatorAvatar(fullName: 'Aiman Yusof'))),
      );

      expect(find.text('A'), findsOneWidget);
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isNull);
    });

    testWidgets('renders "?" when fullName is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NegotiatorAvatar(fullName: ''))),
      );

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('renders a network image when avatarUrl is set', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NegotiatorAvatar(fullName: 'Aiman Yusof', avatarUrl: 'https://example.test/avatar.jpg'),
          ),
        ),
      );

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isA<NetworkImage>());
      expect((avatar.backgroundImage! as NetworkImage).url, 'https://example.test/avatar.jpg');
      expect(find.text('A'), findsNothing);
    });

    testWidgets('shows no online dot when isOnline is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NegotiatorAvatar(fullName: 'Aiman Yusof'))),
      );

      expect(find.byType(Stack), findsNothing);
    });

    testWidgets('shows an online dot when isOnline is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NegotiatorAvatar(fullName: 'Aiman Yusof', isOnline: true)),
        ),
      );

      expect(find.byType(Stack), findsOneWidget);
    });
  });
}
