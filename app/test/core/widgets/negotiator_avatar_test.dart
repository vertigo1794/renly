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

    testWidgets('falls back to initials if the network image fails to load', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NegotiatorAvatar(fullName: 'Aiman Yusof', avatarUrl: 'https://example.test/broken.jpg'),
          ),
        ),
      );

      // flutter_test's HttpClient always returns 400 -- let that failure
      // actually resolve and flow through onBackgroundImageError's setState.
      await tester.pumpAndSettle();

      expect(find.text('A'), findsOneWidget);
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isNull);
    });

    testWidgets('shows no online dot when isOnline is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NegotiatorAvatar(fullName: 'Aiman Yusof'))),
      );

      // Scoped to NegotiatorAvatar's own subtree -- a bare find.byType(Stack)
      // also matches Scaffold's own internal Stack (FAB/body layering),
      // which exists regardless of isOnline and would make this assertion
      // fail even when NegotiatorAvatar itself renders no Stack at all.
      expect(find.descendant(of: find.byType(NegotiatorAvatar), matching: find.byType(Stack)), findsNothing);
    });

    testWidgets('shows an online dot when isOnline is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NegotiatorAvatar(fullName: 'Aiman Yusof', isOnline: true)),
        ),
      );

      expect(find.descendant(of: find.byType(NegotiatorAvatar), matching: find.byType(Stack)), findsOneWidget);
    });

    group('square: true', () {
      testWidgets('renders the initials fallback when avatarUrl is null, no CircleAvatar', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: NegotiatorAvatar(fullName: 'Aiman Yusof', square: true))),
        );

        expect(find.text('A'), findsOneWidget);
        expect(find.byType(CircleAvatar), findsNothing);
        expect(find.byType(Image), findsNothing);
      });

      testWidgets('renders a rounded-square network image when avatarUrl is set', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: NegotiatorAvatar(fullName: 'Aiman Yusof', avatarUrl: 'https://example.test/avatar.jpg', square: true),
            ),
          ),
        );

        expect(find.byType(CircleAvatar), findsNothing);
        final image = tester.widget<Image>(find.byType(Image));
        final provider = image.image as NetworkImage;
        expect(provider.url, 'https://example.test/avatar.jpg');
        expect(find.text('A'), findsNothing);

        final clip = tester.widget<Container>(find.byType(Container).first);
        final decoration = clip.decoration! as BoxDecoration;
        expect(decoration.borderRadius, isNot(null));
      });

      testWidgets('falls back to initials if the square network image fails to load', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: NegotiatorAvatar(fullName: 'Aiman Yusof', avatarUrl: 'https://example.test/broken.jpg', square: true),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Image's own errorBuilder swaps what it PAINTS, not the Image
        // widget instance itself -- it stays in the tree either way, so
        // the real signal here is that the initials text is now showing.
        expect(find.text('A'), findsOneWidget);
      });
    });
  });
}
