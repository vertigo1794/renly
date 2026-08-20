// app/test/features/requirement/requirement_formatting_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/requirement/requirement_formatting.dart';

void main() {
  group('RequirementFormatting.formatBudgetRange', () {
    test('formats a sale range with thousands separators, no suffix', () {
      expect(RequirementFormatting.formatBudgetRange(300000, 500000, 'sale'), 'RM 300,000 - RM 500,000');
    });

    test('formats a rent range with /mo suffix', () {
      expect(RequirementFormatting.formatBudgetRange(2000, 3500, 'rent'), 'RM 2,000 - RM 3,500 /mo');
    });

    test('formats a range under 1000 with no separator', () {
      expect(RequirementFormatting.formatBudgetRange(500, 900, 'sale'), 'RM 500 - RM 900');
    });
  });
}
