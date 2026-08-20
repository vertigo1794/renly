import 'models/requirement.dart';

/// Pure client-side tab filter for My Requirements (open/fulfilled/withdrawn).
class RequirementStatusFilter {
  RequirementStatusFilter._();

  static List<Requirement> byStatus(List<Requirement> requirements, String status) {
    return requirements.where((requirement) => requirement.status == status).toList();
  }
}
