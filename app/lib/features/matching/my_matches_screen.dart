import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/negotiator_avatar.dart';
import '../../core/widgets/r_star_badge.dart';
import '../collaboration/send_cobroke_request_action.dart';
import '../listing/listing_formatting.dart';
import '../notifications/notification_providers.dart';
import '../profile/profile_providers.dart' hide currentNegotiatorIdProvider;
import '../requirement/requirement_formatting.dart';
import 'matching_providers.dart';
import 'models/match_candidate.dart';

/// Restyled from Stitch's "My Matches (Smart Co-Broking Radar)" mockup: a
/// branded header matching Marketplace/My Inventory/Requirement Board's
/// own header pattern, a real live-stats ticker, and a real score-band
/// badge (Hot/Good Match, thresholds pulled from the same 40/100 scoring
/// scale MatchingEngine already uses) instead of the mockup's decorative
/// "Fast Deal" tag. All matches touching the negotiator's own listings or
/// requirements, either side. Reached via "My Matches" on the Home tab.
class MyMatchesScreen extends ConsumerWidget {
  const MyMatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(myMatchesProvider);
    final currentNegotiatorId = ref.watch(currentNegotiatorIdProvider);
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
              child: matchesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
                data: (matches) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              'matching_my_matches_title'.tr(),
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
                            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
                            child: Text(
                              '${matches.length} ${'matching_units_label'.tr()}',
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
                        'matching_my_matches_subtitle'.tr(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                'broadcast_live_badge'.tr(),
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${matches.length} ${'matching_ticker_label'.tr()}',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(PhosphorIcons.lightning(PhosphorIconsStyle.fill), size: 14, color: AppColors.primary),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (matches.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 60),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(color: const Color(0xFFF3F4F1), shape: BoxShape.circle),
                                  child: Icon(PhosphorIcons.target(PhosphorIconsStyle.bold),
                                      size: 32, color: const Color(0xFF94A3B8)),
                                ),
                                const SizedBox(height: 16),
                                Text('matching_empty'.tr()),
                              ],
                            ),
                          ),
                        )
                      else
                        for (final candidate in matches) ...[
                          _MatchCard(
                            candidate: candidate,
                            isMyListing: candidate.listing.negotiatorId == currentNegotiatorId,
                            onTap: () => candidate.listing.negotiatorId == currentNegotiatorId
                                ? context.push('/requirement-board/${candidate.requirement.requirementId}')
                                : context.push('/property/${candidate.listing.listingId}'),
                          ),
                          const SizedBox(height: 16),
                        ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.candidate, required this.isMyListing, required this.onTap});

  final MatchCandidate candidate;
  final bool isMyListing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final owner = isMyListing ? candidate.requirementOwner : candidate.listingOwner;
    final hot = candidate.score >= 80;
    final scoreColor = hot ? const Color(0xFF16A34A) : const Color(0xFFEA580C);

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: scoreColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIcons.lightning(PhosphorIconsStyle.fill), size: 11, color: scoreColor),
                          const SizedBox(width: 4),
                          Text(
                            hot ? 'matching_badge_hot'.tr() : 'matching_badge_good'.tr(),
                            style: TextStyle(color: scoreColor, fontWeight: FontWeight.bold, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFF3F4F1), borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        isMyListing ? 'matching_side_buyer_found'.tr() : 'matching_side_property_found'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${candidate.score}/100',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (isMyListing) ...[
                  Text(
                    RequirementFormatting.formatBudgetRange(
                      candidate.requirement.budgetMin,
                      candidate.requirement.budgetMax,
                      candidate.requirement.transactionType,
                    ),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(PhosphorIcons.mapPin(PhosphorIconsStyle.bold), size: 13, color: const Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(candidate.requirement.area,
                            style: Theme.of(context).textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    ListingFormatting.formatPrice(candidate.listing.price, candidate.listing.transactionType),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(PhosphorIcons.mapPin(PhosphorIconsStyle.bold), size: 13, color: const Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(candidate.listing.area,
                            style: Theme.of(context).textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    NegotiatorAvatar(
                      fullName: owner.fullName,
                      avatarUrl: owner.avatarUrl,
                      isOnline: owner.isOnline,
                      size: 28,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${owner.fullName} (REN: ${owner.renNumber})',
                        style: Theme.of(context).textTheme.labelSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                const SizedBox(height: 12),
                Consumer(
                  builder: (context, ref, _) => BrutalistButton(
                    label: 'cobroke_request_send'.tr(),
                    onPressed: () => sendCobrokeRequest(context, ref, candidate.matchId),
                    icon: PhosphorIcons.handshake(PhosphorIconsStyle.bold),
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
