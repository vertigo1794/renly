import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/core/widgets/brutalist_button.dart';

void main() {
  group('BrutalistButton', () {
    testWidgets('renders the given label', (tester) async {
      await tester.pumpWidget(MaterialApp(home: BrutalistButton(label: 'Tap me', onPressed: () {})));
      expect(find.text('Tap me'), findsOneWidget);
    });

    testWidgets('primary variant applies a hard shadow', (tester) async {
      await tester.pumpWidget(MaterialApp(home: BrutalistButton(label: 'Primary', onPressed: () {})));
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.boxShadow, isNotNull);
      expect(decoration.boxShadow!.single.blurRadius, 0);
      expect(decoration.boxShadow!.single.offset, const Offset(4, 4));
    });

    testWidgets('secondary variant has no shadow and a transparent fill', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: BrutalistButton(label: 'Secondary', onPressed: () {}, variant: BrutalistButtonVariant.secondary),
      ));
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.boxShadow, isNull);
      expect(decoration.color, Colors.transparent);
    });

    testWidgets('calls onPressed when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(home: BrutalistButton(label: 'Tap', onPressed: () => tapped = true)));
      await tester.tap(find.byType(BrutalistButton));
      expect(tapped, isTrue);
    });

    testWidgets('renders without error when onPressed is null (disabled)', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BrutalistButton(label: 'Disabled', onPressed: null)));
      expect(find.text('Disabled'), findsOneWidget);
      await tester.tap(find.byType(BrutalistButton));
      // No exception thrown, no state to assert -- InkWell(onTap: null) is
      // Flutter's own disabled-tap contract, not reimplemented here.
    });
  });
}
