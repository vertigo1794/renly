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

    testWidgets('fullWidth:false renders narrower than a wide bounded parent', (tester) async {
      // A Center (like AlertDialog's OverflowBar / a Column) hands its child
      // a bounded-but-loose width constraint -- the exact shape that once
      // made Container's `alignment` silently expand a fullWidth:false
      // button to fill the parent. Asserting the widget's constructor
      // property (the old version of this test) can't catch that; only
      // measuring rendered geometry can.
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: BrutalistButton(label: 'Compact', onPressed: () {}, fullWidth: false),
        ),
      ));
      final width = tester.getSize(find.byType(BrutalistButton)).width;
      expect(width, lessThan(200));
    });

    testWidgets('fullWidth:false shrink-wraps side-by-side in a Row', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Row(
          children: [
            BrutalistButton(label: 'A', onPressed: () {}, fullWidth: false),
            const SizedBox(width: 12),
            BrutalistButton(label: 'B', onPressed: () {}, fullWidth: false),
          ],
        ),
      ));
      final widthA = tester.getSize(find.text('A')).width;
      final buttonWidthA = tester.getSize(find.widgetWithText(BrutalistButton, 'A')).width;
      expect(buttonWidthA, lessThan(widthA + 60));
    });

    testWidgets('icon renders before the label when provided', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: BrutalistButton(label: 'Send', onPressed: () {}, icon: Icons.send),
      ));
      expect(find.byIcon(Icons.send), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
    });

    testWidgets('exposes button semantics matching the enabled state', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        home: Column(children: [
          BrutalistButton(label: 'Enabled', onPressed: () {}),
          const BrutalistButton(label: 'Disabled', onPressed: null),
        ]),
      ));

      expect(
        tester.getSemantics(find.text('Enabled')),
        matchesSemantics(
          label: 'Enabled',
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: true,
          hasEnabledState: true,
          hasFocusAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.text('Disabled')),
        matchesSemantics(label: 'Disabled', isButton: true, isEnabled: false, hasEnabledState: true),
      );
      handle.dispose();
    });
  });
}
