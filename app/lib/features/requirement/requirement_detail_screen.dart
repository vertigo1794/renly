import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/negotiator_avatar.dart';
import '../../core/widgets/r_star_badge.dart';
import '../../core/widgets/signed_photo.dart';
import '../collaboration/cobroke_request_providers.dart' hide currentNegotiatorIdProvider;
import '../collaboration/send_cobroke_request_action.dart';
import '../listing/listing_formatting.dart';
import '../matching/matching_providers.dart' hide currentNegotiatorIdProvider;
import '../matching/models/match_candidate.dart';
import '../profile/profile_providers.dart' hide currentNegotiatorIdProvider;
import 'models/requirement.dart';
import 'requirement_formatting.dart';
import 'requirement_providers.dart';
import '../subscription/subscription_providers.dart' hide currentNegotiatorIdProvider;

/// Restyled from Stitch's "Buyer Requirement Detail (Ultra-Premium
/// Mandate)" mockup, mirroring PropertyDetailScreen's own already-
/// restyled architecture (hero photos, an `_OverviewCard` with a real
/// spec grid, an agent card, an action bar) so the two symmetric detail
/// screens share one visual language. Surfaces several real fields this
/// screen never showed before -- `bathroomsMin`/`builtUpSqftMin`/
/// `parkingBaysMin`/`floorLevelMin`/`furnishingPreference`/
/// `tenurePreference` in the spec grid, `loanReady`/`urgentViewingRequired`
/// as colored tags, `desiredCommissionSplitPercent` as its own terms card
/// -- all already collected by PostRequirementScreen but never rendered
/// anywhere until now, instead of inventing the mockup's own decorative
/// sub-captions.
class RequirementDetailScreen extends ConsumerStatefulWidget {
  const RequirementDetailScreen({super.key, required this.requirementId});

  final String requirementId;

  @override
  ConsumerState<RequirementDetailScreen> createState() => _RequirementDetailScreenState();
}

class _RequirementDetailScreenState extends ConsumerState<RequirementDetailScreen> {
  String _statusLabel(String status) {
    switch (status) {
      case 'open':
        return 'requirement_tab_open'.tr();
      case 'fulfilled':
        return 'requirement_tab_fulfilled'.tr();
      default:
        return 'inventory_tab_withdrawn'.tr();
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return const Color(0xFF16A34A);
      case 'fulfilled':
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFF64748B);
    }
  }

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

  Future<void> _delete(Requirement requirement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('requirement_delete_confirm_title'.tr()),
        content: Text('requirement_delete_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('inventory_delete_cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'inventory_delete_confirm_button'.tr(),
              style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(requirementRepositoryProvider).deleteRequirement(widget.requirementId);
      ref.invalidate(boardRequirementsProvider);
      ref.invalidate(myRequirementsProvider(requirement.negotiatorId));
      ref.invalidate(activeRequirementCountProvider(requirement.negotiatorId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('requirement_delete_success'.tr())));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('listing_error_generic'.tr())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final requirementAsync = ref.watch(requirementDetailProvider(widget.requirementId));
    final currentNegotiatorId = ref.watch(currentNegotiatorIdProvider);
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAF7),
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: const Color(0xFFF9FAF7),
        elevation: 0,
        title: Row(
          children: [
            const RStarBadge(size: 28),
            const SizedBox(width: 8),
            Text(
              'app_name'.tr(),
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: AppColors.ink,
                    fontSize: 20,
                    letterSpacing: -1.0,
                    height: 1,
                  ),
            ),
          ],
        ),
        actions: [
          profileAsync.maybeWhen(
            data: (profile) => profile.renNumber == null
                ? const SizedBox.shrink()
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.ink.withValues(alpha: 0.1)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'REN ${profile.renNumber}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: requirementAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
        data: (requirement) {
          final isOwner = currentNegotiatorId != null && currentNegotiatorId == requirement.negotiatorId;
          // Only watched for the owner -- same Realtime-subscription reasoning
          // as PropertyDetailScreen.
          var atCap = false;
          // Same protection PropertyDetailScreen's own Delete gives a listing
          // with an accepted co-broke request -- a real deal with chat/
          // agreement history worth preserving, not something Delete should
          // silently wipe out from under an active collaboration.
          var hasAcceptedRequest = false;
          if (isOwner) {
            final tierAsync = ref.watch(subscriptionStatusProvider);
            final countAsync = ref.watch(activeRequirementCountProvider(currentNegotiatorId));
            atCap = tierAsync.valueOrNull?.tier == 'free' && (countAsync.valueOrNull ?? 0) >= 3;
            final receivedAsync = ref.watch(receivedRequestsProvider);
            final sentAsync = ref.watch(sentRequestsProvider);
            hasAcceptedRequest = [...?receivedAsync.valueOrNull, ...?sentAsync.valueOrNull].any(
              (c) => c.match.requirement.requirementId == requirement.requirementId && c.request.status == 'accepted',
            );
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (requirement.photoUrls.isNotEmpty) ...[
                    _PhotoCarousel(requirement: requirement),
                    const SizedBox(height: 16),
                  ],
                  _OverviewCard(
                    requirement: requirement,
                    statusLabel: _statusLabel(requirement.status),
                    statusColor: _statusColor(requirement.status),
                  ),
                  if (requirement.desiredCommissionSplitPercent != null) ...[
                    const SizedBox(height: 16),
                    _TermsCard(percent: requirement.desiredCommissionSplitPercent!),
                  ],
                  const SizedBox(height: 16),
                  _AgentCard(negotiatorId: requirement.negotiatorId),
                  const SizedBox(height: 16),
                  if (isOwner)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        BrutalistButton(
                          label: 'matching_view_matches'.tr(),
                          onPressed: () => context.push('/requirement-board/${widget.requirementId}/matches'),
                        ),
                        const SizedBox(height: 8),
                        if (requirement.status != 'fulfilled') ...[
                          BrutalistButton(
                            label: 'requirement_mark_fulfilled'.tr(),
                            variant: BrutalistButtonVariant.secondary,
                            onPressed: () => _changeStatus(requirement, 'fulfilled'),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (requirement.status != 'withdrawn') ...[
                          BrutalistButton(
                            label: 'requirement_withdraw'.tr(),
                            variant: BrutalistButtonVariant.secondary,
                            onPressed: () => _changeStatus(requirement, 'withdrawn'),
                          ),
                          const SizedBox(height: 8),
                        ],
                        BrutalistButton(
                          label: hasAcceptedRequest
                              ? '${'requirement_action_delete'.tr()} (${'requirement_delete_blocked_message'.tr()})'
                              : 'requirement_action_delete'.tr(),
                          variant: BrutalistButtonVariant.dark,
                          onPressed: hasAcceptedRequest ? null : () => _delete(requirement),
                        ),
                        const SizedBox(height: 8),
                        if (requirement.status != 'open') ...[
                          if (atCap) ...[
                            Text(
                              'requirement_cap_reached_message'.tr(),
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                            const SizedBox(height: 8),
                          ],
                          BrutalistButton(
                            label: 'requirement_reactivate'.tr(),
                            variant: BrutalistButtonVariant.secondary,
                            onPressed: atCap ? null : () => _changeStatus(requirement, 'open'),
                          ),
                        ],
                      ],
                    )
                  else if (currentNegotiatorId != null)
                    _NonOwnerActionBar(requirement: requirement, viewerId: currentNegotiatorId),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Mirrors PropertyDetailScreen's own non-owner action bar: "Request
/// Co-Broke" is only enabled once the matching engine has already scored a
/// real Match between this requirement and one of the viewer's own
/// listings -- see MatchingEngine.score's mandatory filters and >=40
/// qualifying threshold. Previously this screen showed no action bar at
/// all for non-owners, unlike its listing-side mirror.
class _NonOwnerActionBar extends ConsumerWidget {
  const _NonOwnerActionBar({required this.requirement, required this.viewerId});

  final Requirement requirement;
  final String viewerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(matchesForRequirementProvider(requirement.requirementId));
    MatchCandidate? ownMatch;
    for (final candidate in matchesAsync.valueOrNull ?? const <MatchCandidate>[]) {
      if (candidate.listing.negotiatorId == viewerId) {
        ownMatch = candidate;
        break;
      }
    }

    return Tooltip(
      message: ownMatch == null ? 'property_request_co_broke_disabled_reason'.tr() : '',
      child: BrutalistButton(
        label: 'cobroke_request_send'.tr(),
        onPressed: ownMatch == null ? null : () => sendCobrokeRequest(context, ref, ownMatch!.matchId),
      ),
    );
  }
}

class _PhotoCarousel extends StatelessWidget {
  const _PhotoCarousel({required this.requirement});

  final Requirement requirement;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: PageView(
        children: [
          for (final photoPath in requirement.photoUrls)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Consumer(
                  builder: (context, ref, _) => SignedPhoto(
                    path: photoPath,
                    signedUrlFetcher: ref.read(requirementRepositoryProvider).createSignedUrl,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.requirement, required this.statusLabel, required this.statusColor});

  final Requirement requirement;
  final String statusLabel;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            RequirementFormatting.formatBudgetRange(requirement.budgetMin, requirement.budgetMax, requirement.transactionType),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(PhosphorIcons.mapPin(PhosphorIconsStyle.bold), size: 14, color: const Color(0xFF94A3B8)),
              const SizedBox(width: 4),
              Flexible(
                child: Text('${requirement.area}, ${requirement.state}', style: Theme.of(context).textTheme.bodyMedium),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${'listing_property_type_${requirement.propertyType}'.tr()} · '
            '${'listing_transaction_type_${requirement.transactionType}'.tr()}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          _SpecGrid(requirement: requirement),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor,
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              if (requirement.loanReady)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF16A34A), borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill), size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'requirement_badge_loan_ready'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              if (requirement.urgentViewingRequired)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFEA580C), borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIcons.clockCountdown(PhosphorIconsStyle.fill), size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'requirement_badge_urgent'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The buyer-criteria stats (beds/min baths/min sqft/min parking/min floor/
/// furnishing/tenure preference), same boxed-tile visual language as
/// PropertyDetailScreen's own `_SpecGrid` -- real fields only, all already
/// collected by PostRequirementScreen but never displayed anywhere before
/// this restyle.
class _SpecGrid extends StatelessWidget {
  const _SpecGrid({required this.requirement});

  final Requirement requirement;

  @override
  Widget build(BuildContext context) {
    final cards = <_SpecCardData>[
      if (requirement.bedrooms != null) _SpecCardData(Icons.bed, '${requirement.bedrooms}', 'inventory_stat_beds'.tr()),
      if (requirement.bathroomsMin != null) _SpecCardData(Icons.bathtub, '${requirement.bathroomsMin}', 'requirement_stat_baths_min'.tr()),
      if (requirement.builtUpSqftMin != null)
        _SpecCardData(PhosphorIcons.ruler(PhosphorIconsStyle.bold), ListingFormatting.formatSqft(requirement.builtUpSqftMin!),
            'requirement_stat_sqft_min'.tr()),
      if (requirement.parkingBaysMin != null)
        _SpecCardData(PhosphorIcons.car(PhosphorIconsStyle.bold), '${requirement.parkingBaysMin}', 'requirement_stat_parking_min'.tr()),
      if (requirement.floorLevelMin != null)
        _SpecCardData(PhosphorIcons.stackSimple(PhosphorIconsStyle.bold), '${requirement.floorLevelMin}', 'requirement_stat_floor_min'.tr()),
      if (requirement.furnishingPreference != null)
        _SpecCardData(
          PhosphorIcons.armchair(PhosphorIconsStyle.bold),
          requirement.furnishingPreference == 'furnished'
              ? 'listing_furnishing_furnished'.tr()
              : requirement.furnishingPreference == 'partially_furnished'
                  ? 'listing_furnishing_partially_furnished'.tr()
                  : 'listing_furnishing_unfurnished'.tr(),
          'listing_stat_furnishing'.tr(),
        ),
      if (requirement.tenurePreference != null)
        _SpecCardData(
          PhosphorIcons.fileText(PhosphorIconsStyle.bold),
          requirement.tenurePreference == 'freehold' ? 'listing_tenure_freehold'.tr() : 'listing_tenure_leasehold'.tr(),
          'listing_field_tenure'.tr(),
        ),
    ];

    if (cards.isEmpty) return const SizedBox.shrink();

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.1,
      children: [for (final card in cards) _SpecCard(card)],
    );
  }
}

class _SpecCardData {
  const _SpecCardData(this.icon, this.value, this.caption);

  final IconData icon;
  final String value;
  final String caption;
}

class _SpecCard extends StatelessWidget {
  const _SpecCard(this.data);

  final _SpecCardData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(data.icon, size: 18),
          const SizedBox(height: 4),
          Text(
            data.value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(
            data.caption,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF64748B), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _TermsCard extends StatelessWidget {
  const _TermsCard({required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    final split = percent.round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Row(
        children: [
          Icon(PhosphorIcons.handshake(PhosphorIconsStyle.bold), size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('requirement_terms_title'.tr(), style: Theme.of(context).textTheme.titleMedium)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.black)),
            child: Text('$split%', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _AgentCard extends ConsumerWidget {
  const _AgentCard({required this.negotiatorId});

  final String negotiatorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownerAsync = ref.watch(requirementOwnerProvider(negotiatorId));

    return ownerAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (owner) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Row(
          children: [
            NegotiatorAvatar(
              fullName: owner.fullName,
              avatarUrl: owner.avatarUrl,
              isOnline: owner.isOnline,
              size: 56,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(owner.fullName, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
                      if (owner.verificationStatus == 'approved') ...[
                        const SizedBox(width: 4),
                        Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.fill), size: 15, color: const Color(0xFF059669)),
                      ],
                    ],
                  ),
                  Text(
                    owner.agencyName == null ? 'REN: ${owner.renNumber}' : 'REN: ${owner.renNumber} • ${owner.agencyName}',
                    style: Theme.of(context).textTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
