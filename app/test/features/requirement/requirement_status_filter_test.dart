// app/test/features/requirement/requirement_status_filter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/requirement/models/requirement.dart';
import 'package:renly/features/requirement/requirement_status_filter.dart';

Requirement _requirement(String id, String status) {
  return Requirement(
    requirementId: id,
    negotiatorId: 'n-1',
    propertyType: 'apartment',
    transactionType: 'sale',
    state: 'Selangor',
    area: 'PJ',
    budgetMin: 100000,
    budgetMax: 200000,
    photoUrls: const [],
    status: status,
  );
}

void main() {
  group('RequirementStatusFilter.byStatus', () {
    test('returns only requirements matching the given status', () {
      final requirements = [_requirement('1', 'open'), _requirement('2', 'fulfilled'), _requirement('3', 'open')];
      final result = RequirementStatusFilter.byStatus(requirements, 'open');
      expect(result.map((r) => r.requirementId), ['1', '3']);
    });

    test('returns empty list when nothing matches', () {
      final requirements = [_requirement('1', 'open')];
      expect(RequirementStatusFilter.byStatus(requirements, 'withdrawn'), isEmpty);
    });
  });
}
