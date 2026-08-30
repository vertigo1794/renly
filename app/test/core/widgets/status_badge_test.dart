import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/core/theme/app_colors.dart';
import 'package:renly/core/widgets/status_badge.dart';

void main() {
  group('StatusBadge', () {
    testWidgets('renders the given label', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: StatusBadge(label: 'Active')));
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('uses the brand accent color as its fill', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: StatusBadge(label: 'Sold')));
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.accent);
    });

    testWidgets('has an ink border', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: StatusBadge(label: 'Withdrawn')));
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
    });
  });
}
