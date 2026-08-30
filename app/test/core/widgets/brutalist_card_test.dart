import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/core/widgets/brutalist_card.dart';

void main() {
  group('BrutalistCard', () {
    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BrutalistCard(child: Text('Inside'))));
      expect(find.text('Inside'), findsOneWidget);
    });

    testWidgets('applies a hard shadow decoration', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BrutalistCard(child: Text('x'))));
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.boxShadow, isNotNull);
      expect(decoration.boxShadow!.single.blurRadius, 0);
      expect(decoration.boxShadow!.single.offset, const Offset(4, 4));
    });

    testWidgets('uses 16px default padding', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BrutalistCard(child: Text('x'))));
      final container = tester.widget<Container>(find.byType(Container));
      expect(container.padding, const EdgeInsets.all(16));
    });

    testWidgets('accepts a custom padding override', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: BrutalistCard(padding: EdgeInsets.all(8), child: Text('x')),
      ));
      final container = tester.widget<Container>(find.byType(Container));
      expect(container.padding, const EdgeInsets.all(8));
    });
  });
}
