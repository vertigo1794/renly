import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:renly/core/theme/app_colors.dart';
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

    testWidgets('dark variant applies an ink fill, a hard shadow, and lime text', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: BrutalistButton(label: 'Dark', onPressed: () {}, variant: BrutalistButtonVariant.dark),
      ));
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.ink);
      expect(decoration.boxShadow, isNotNull);
      expect(decoration.boxShadow!.single.offset, const Offset(4, 4));

      final text = tester.widget<Text>(find.text('Dark'));
      expect(text.style?.color, AppColors.primaryContainer);
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

    testWidgets('fullWidth:false pair renders side-by-side inside a real AlertDialog', (tester) async {
      // Regression guard for the actual reported bug shape: a bare Row
      // never triggers Container's alignment-expansion issue (Row hands
      // its children unbounded width), so a Row-only test can pass against
      // a genuinely broken widget. AlertDialog's actions render through
      // OverflowBar, which hands each action a bounded-but-loose width --
      // the exact context that was silently broken before the
      // IntrinsicWidth fix. Verified empirically to need >= ~380dp with
      // this widget's current compact padding.
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    actionsOverflowButtonSpacing: 8,
                    title: const Text('Test'),
                    actions: [
                      BrutalistButton(
                        label: 'Cancel',
                        onPressed: () {},
                        variant: BrutalistButtonVariant.secondary,
                        fullWidth: false,
                      ),
                      BrutalistButton(
                        label: 'Submit',
                        onPressed: () {},
                        fullWidth: false,
                        icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
                      ),
                    ],
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final rectA = tester.getRect(find.widgetWithText(BrutalistButton, 'Cancel'));
      final rectB = tester.getRect(find.widgetWithText(BrutalistButton, 'Submit'));
      expect(rectA.top, rectB.top, reason: 'both actions should render on the same row, not stacked');
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
