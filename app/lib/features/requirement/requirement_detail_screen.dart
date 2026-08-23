import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/signed_photo.dart';
import 'models/requirement.dart';
import 'requirement_formatting.dart';
import 'requirement_providers.dart';
import '../subscription/subscription_providers.dart' hide currentNegotiatorIdProvider;

/// Symmetric with PropertyDetailScreen: photo carousel, criteria
/// breakdown, posting negotiator, and owner-only status actions.
class RequirementDetailScreen extends ConsumerStatefulWidget {
  const RequirementDetailScreen({super.key, required this.requirementId});

  final String requirementId;

  @override
  ConsumerState<RequirementDetailScreen> createState() => _RequirementDetailScreenState();
}

class _RequirementDetailScreenState extends ConsumerState<RequirementDetailScreen> {
  /// Takes the requirement (not just the new status) so the two list
  /// providers can be invalidated too -- otherwise a requirement marked
  /// fulfilled here stays on the board and in My Requirements' Open tab
  /// until restart.
  Future<void> _changeStatus(Requirement requirement, String status) async {
    final repository = ref.read(requirementRepositoryProvider);
    try {
      await repository.updateRequirementStatus(requirementId: widget.requirementId, status: status);
      ref.invalidate(requirementDetailProvider(widget.requirementId));
      ref.invalidate(boardRequirementsProvider);
      ref.invalidate(myRequirementsProvider(requirement.negotiatorId));
      // Same reasoning as PropertyDetailScreen: the non-autoDispose cap counter
      // would otherwise keep a free-tier user falsely locked out of posting.
      ref.invalidate(activeRequirementCountProvider(requirement.negotiatorId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('listing_error_generic'.tr())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final requirementAsync = ref.watch(requirementDetailProvider(widget.requirementId));
    final currentNegotiatorId = ref.watch(currentNegotiatorIdProvider);

    return Scaffold(
      appBar: AppBar(),
      body: requirementAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
        data: (requirement) {
          final isOwner = currentNegotiatorId != null && currentNegotiatorId == requirement.negotiatorId;
          // Only watched for the owner -- same Realtime-subscription reasoning
          // as PropertyDetailScreen.
          var atCap = false;
          if (isOwner) {
            final tierAsync = ref.watch(subscriptionStatusProvider);
            final countAsync = ref.watch(activeRequirementCountProvider(currentNegotiatorId));
            atCap = tierAsync.valueOrNull?.tier == 'free' && (countAsync.valueOrNull ?? 0) >= 3;
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (requirement.photoUrls.isNotEmpty)
                    SizedBox(
                      height: 220,
                      child: PageView(
                        children: [
                          for (final photoPath in requirement.photoUrls)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SignedPhoto(
                                  path: photoPath,
                                  signedUrlFetcher: ref.read(requirementRepositoryProvider).createSignedUrl,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    RequirementFormatting.formatBudgetRange(
                      requirement.budgetMin,
                      requirement.budgetMax,
                      requirement.transactionType,
                    ),
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${'listing_property_type_${requirement.propertyType}'.tr()} · '
                    '${'listing_transaction_type_${requirement.transactionType}'.tr()}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (requirement.bedrooms != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.bed),
                        const SizedBox(width: 4),
                        Text('${requirement.bedrooms}'),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text('property_location'.tr(), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('${requirement.area}, ${requirement.state}',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  Builder(builder: (context) {
                    final ownerAsync = ref.watch(requirementOwnerProvider(requirement.negotiatorId));
                    return ownerAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (error, stack) => const SizedBox.shrink(),
                      data: (owner) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(owner.fullName, style: Theme.of(context).textTheme.titleMedium),
                          Text('REN: ${owner.renNumber}', style: Theme.of(context).textTheme.labelSmall),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                  if (isOwner) ...[
                    OutlinedButton(
                      onPressed: () => context.push('/requirement-board/${widget.requirementId}/matches'),
                      child: Text('matching_view_matches'.tr()),
                    ),
                    const SizedBox(height: 8),
                    if (requirement.status != 'fulfilled')
                      OutlinedButton(
                        onPressed: () => _changeStatus(requirement, 'fulfilled'),
                        child: Text('requirement_mark_fulfilled'.tr()),
                      ),
                    if (requirement.status != 'withdrawn')
                      OutlinedButton(
                        onPressed: () => _changeStatus(requirement, 'withdrawn'),
                        child: Text('requirement_withdraw'.tr()),
                      ),
                    if (requirement.status != 'open') ...[
                      if (atCap) ...[
                        Text(
                          'requirement_cap_reached_message'.tr(),
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                        const SizedBox(height: 8),
                      ],
                      OutlinedButton(
                        onPressed: atCap ? null : () => _changeStatus(requirement, 'open'),
                        child: Text('requirement_reactivate'.tr()),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
