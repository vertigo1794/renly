// app/lib/features/requirement/requirement_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import '../listing/models/listing_owner.dart';
import 'models/requirement.dart';
import 'requirement_repository.dart';

final requirementRepositoryProvider = Provider<RequirementRepository>((ref) {
  return RequirementRepository(Supabase.instance.client);
});

/// Same session-state read as listing_providers.dart's
/// currentNegotiatorIdProvider -- duplicated here rather than imported from
/// the listing feature, so the requirement feature only depends on auth,
/// not on a sibling feature, for something this basic.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

final boardRequirementsProvider = FutureProvider<List<Requirement>>((ref) {
  return ref.watch(requirementRepositoryProvider).fetchBoardRequirements();
});

final myRequirementsProvider = FutureProvider.family<List<Requirement>, String>((ref, negotiatorId) {
  return ref.watch(requirementRepositoryProvider).fetchOwnRequirements(negotiatorId);
});

final requirementDetailProvider = FutureProvider.family<Requirement, String>((ref, requirementId) {
  return ref.watch(requirementRepositoryProvider).fetchRequirementById(requirementId);
});

final requirementOwnerProvider = FutureProvider.family<ListingOwner, String>((ref, negotiatorId) {
  return ref.watch(requirementRepositoryProvider).fetchRequirementOwner(negotiatorId);
});
