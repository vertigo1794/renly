// app/lib/features/requirement/my_requirements_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/r_star_badge.dart';
import '../../core/widgets/signed_photo.dart';
import '../matching/matching_providers.dart' hide currentNegotiatorIdProvider;
import '../notifications/notification_providers.dart';
import '../profile/profile_providers.dart' hide currentNegotiatorIdProvider;
import 'models/requirement.dart';
import 'requirement_formatting.dart';
import 'requirement_providers.dart';
import 'requirement_status_filter.dart';

/// Restyled from Stitch's "My Requirements (Buyer Demands & Radar)"
/// mockup: a branded header matching My Inventory's own (back button --
/// this is a pushed route outside the bottom-nav shell, same reasoning),
/// a real open/fulfilled/withdrawn stat row, and a real "match radar"
/// insight per card reusing myMatchesProvider (the same data My Inventory's
/// own top-match banner already surfaces, just from the requirement side)
/// instead of the mockup's decorative match-count figure.
class MyRequirementsScreen extends ConsumerStatefulWidget {
  const MyRequirementsScreen({super.key});

  @override
  ConsumerState<MyRequirementsScreen> createState() => _MyRequirementsScreenState();
}

class _MyRequirementsScreenState extends ConsumerState<MyRequirementsScreen> {
  String _selectedStatus = 'open';

  @override
  Widget build(BuildContext context) {
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);
    final profileAsync = ref.watch(myProfileProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAF7),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(PhosphorIcons.arrowLeft(PhosphorIconsStyle.bold)),
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/home');
                      }
                    },
                  ),
                  const SizedBox(width: 4),
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
                  const Spacer(),
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
                  const SizedBox(width: 8),
                  Stack(
                    children: [
                      IconButton(
                        icon: Icon(PhosphorIcons.bellSimple(PhosphorIconsStyle.bold)),
                        onPressed: () => context.push('/notifications'),
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: negotiatorId == null
                  ? const Center(child: CircularProgressIndicator())
                  : Consumer(
                      builder: (context, ref, _) {
                        final requirementsAsync = ref.watch(myRequirementsProvider(negotiatorId));
                        return requirementsAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
                          data: (requirements) {
                            final openCount = RequirementStatusFilter.byStatus(requirements, 'open').length;
                            final fulfilledCount = RequirementStatusFilter.byStatus(requirements, 'fulfilled').length;
                            final withdrawnCount = RequirementStatusFilter.byStatus(requirements, 'withdrawn').length;
                            final filtered = RequirementStatusFilter.byStatus(requirements, _selectedStatus);

                            return RefreshIndicator(
                              onRefresh: () async => ref.invalidate(myRequirementsProvider(negotiatorId)),
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'requirement_my_title'.tr(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineMedium
                                              ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1.0),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration:
                                            BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
                                        child: Text(
                                          '${requirements.length} ${'requirement_units_label'.tr()}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'requirement_my_subtitle'.tr(),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _StatMini(
                                          value: '$openCount',
                                          label: 'requirement_tab_open'.tr().toUpperCase(),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _StatMini(
                                          value: '$fulfilledCount',
                                          label: 'requirement_tab_fulfilled'.tr().toUpperCase(),
                                          highlight: true,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _StatMini(
                                          value: '$withdrawnCount',
                                          label: 'inventory_tab_withdrawn'.tr().toUpperCase(),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    height: 36,
                                    child: ListView(
                                      scrollDirection: Axis.horizontal,
                                      children: [
                                        _TabPill(
                                          label: 'requirement_tab_open'.tr(),
                                          selected: _selectedStatus == 'open',
                                          onTap: () => setState(() => _selectedStatus = 'open'),
                                        ),
                                        const SizedBox(width: 8),
                                        _TabPill(
                                          label: 'requirement_tab_fulfilled'.tr(),
                                          selected: _selectedStatus == 'fulfilled',
                                          onTap: () => setState(() => _selectedStatus = 'fulfilled'),
                                        ),
                                        const SizedBox(width: 8),
                                        _TabPill(
                                          label: 'inventory_tab_withdrawn'.tr(),
                                          selected: _selectedStatus == 'withdrawn',
                                          onTap: () => setState(() => _selectedStatus = 'withdrawn'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  if (filtered.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 60),
                                      child: Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 72,
                                              height: 72,
                                              decoration:
                                                  BoxDecoration(color: const Color(0xFFF3F4F1), shape: BoxShape.circle),
                                              child: Icon(PhosphorIcons.target(PhosphorIconsStyle.bold),
                                                  size: 32, color: const Color(0xFF94A3B8)),
                                            ),
                                            const SizedBox(height: 16),
                                            Text('requirement_my_empty'.tr()),
                                          ],
                                        ),
                                      ),
                                    )
                                  else
                                    for (final requirement in filtered) ...[
                                      _MyRequirementCard(
                                        requirement: requirement,
                                        onTap: () => context.push('/requirement-board/${requirement.requirementId}'),
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: BrutalistButton(
                label: 'requirement_post_new'.tr(),
                icon: PhosphorIcons.plus(PhosphorIconsStyle.bold),
                onPressed: () => context.push('/post-requirement'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatMini extends StatelessWidget {
  const _StatMini({required this.value, required this.label, this.highlight = false});

  final String value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ? Colors.black : const Color(0xFFE2E5DC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF64748B), letterSpacing: 0.4, fontSize: 9),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.black : const Color(0xFFE2E5DC)),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected ? AppColors.primary : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
      ),
    );
  }
}

class _MyRequirementCard extends StatelessWidget {
  const _MyRequirementCard({required this.requirement, required this.onTap});

  final Requirement requirement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E5DC)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (requirement.photoUrls.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: Consumer(
                        builder: (context, ref, _) => SignedPhoto(
                          path: requirement.photoUrls.first,
                          signedUrlFetcher: ref.read(requirementRepositoryProvider).createSignedUrl,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        RequirementFormatting.formatBudgetRange(
                          requirement.budgetMin,
                          requirement.budgetMax,
                          requirement.transactionType,
                        ),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Text(
                        requirement.propertyType,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(PhosphorIcons.mapPin(PhosphorIconsStyle.bold), size: 13, color: const Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${requirement.area}, ${requirement.state}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF64748B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (requirement.loanReady || requirement.urgentViewingRequired) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (requirement.loanReady)
                        _Tag(
                          label: 'requirement_badge_loan_ready'.tr(),
                          color: const Color(0xFF16A34A),
                          icon: PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                        ),
                      if (requirement.urgentViewingRequired)
                        _Tag(
                          label: 'requirement_badge_urgent'.tr(),
                          color: const Color(0xFFEA580C),
                          icon: PhosphorIcons.clockCountdown(PhosphorIconsStyle.fill),
                        ),
                    ],
                  ),
                ],
                if (requirement.status == 'open')
                  Consumer(
                    builder: (context, ref, _) {
                      final matchesAsync = ref.watch(myMatchesProvider);
                      final forThisRequirement = matchesAsync.maybeWhen(
                        data: (matches) =>
                            matches.where((m) => m.requirement.requirementId == requirement.requirementId).toList(),
                        orElse: () => const [],
                      );
                      if (forThisRequirement.isEmpty) return const SizedBox.shrink();
                      forThisRequirement.sort((a, b) => b.score.compareTo(a.score));
                      final topMatch = forThisRequirement.first;
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                  '${topMatch.score}%',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  forThisRequirement.length > 1
                                      ? '${forThisRequirement.length} ${'requirement_insight_matches_label'.tr()}'
                                      : '${'requirement_insight_matches_label'.tr()}: ${topMatch.listingOwner.fullName}',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
        ],
      ),
    );
  }
}
