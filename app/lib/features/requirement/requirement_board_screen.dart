// app/lib/features/requirement/requirement_board_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/negotiator_avatar.dart';
import '../../core/widgets/r_star_badge.dart';
import '../../core/widgets/signed_photo.dart';
import '../notifications/notification_providers.dart';
import '../profile/profile_providers.dart' hide currentNegotiatorIdProvider;
import 'models/requirement.dart';
import 'requirement_formatting.dart';
import 'requirement_providers.dart';

enum _PropertyFilter { all, residential, commercial }

/// Restyled from Stitch's "Requirement Board (Community Buyer Demands)"
/// mockup: a branded header matching Marketplace/My Inventory's own
/// header pattern, a real live-stats ticker, real property-type filter
/// pills (same data field/pattern as MarketplaceScreen's), and premium
/// cards -- including 2 genuinely real, previously-undisplayed-anywhere-
/// on-this-screen badges (Loan Ready / Urgent Viewing, both self-attested
/// fields already collected by PostRequirementScreen) instead of the
/// mockup's decorative "Fast Deal" tag, which has no backing data.
class RequirementBoardScreen extends ConsumerStatefulWidget {
  const RequirementBoardScreen({super.key});

  @override
  ConsumerState<RequirementBoardScreen> createState() => _RequirementBoardScreenState();
}

class _RequirementBoardScreenState extends ConsumerState<RequirementBoardScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _PropertyFilter _filter = _PropertyFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Requirement> _applyFilters(List<Requirement> requirements) {
    var result = requirements;
    switch (_filter) {
      case _PropertyFilter.all:
        break;
      case _PropertyFilter.residential:
        result = result.where((r) => r.propertyType != 'commercial').toList();
      case _PropertyFilter.commercial:
        result = result.where((r) => r.propertyType == 'commercial').toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      result = result.where((r) => r.area.toLowerCase().contains(q) || r.state.toLowerCase().contains(q)).toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final requirementsAsync = ref.watch(boardRequirementsProvider);
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
              child: requirementsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
                data: (requirements) {
                  final filtered = _applyFilters(requirements);
                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(boardRequirementsProvider),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                'requirement_board_title'.tr(),
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
                          'requirement_board_subtitle'.tr(),
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
                                  '${requirements.length} ${'requirement_board_ticker_label'.tr()}',
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
                        const SizedBox(height: 14),
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'requirement_board_search_hint'.tr(),
                            prefixIcon: Icon(PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.bold)),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: Color(0xFFE2E5DC)),
                            ),
                          ),
                          onChanged: (value) => setState(() => _query = value),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 36,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _FilterPill(
                                label: 'requirement_filter_all'.tr(),
                                selected: _filter == _PropertyFilter.all,
                                onTap: () => setState(() => _filter = _PropertyFilter.all),
                              ),
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: 'requirement_filter_residential'.tr(),
                                selected: _filter == _PropertyFilter.residential,
                                onTap: () => setState(() => _filter = _PropertyFilter.residential),
                              ),
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: 'requirement_filter_commercial'.tr(),
                                selected: _filter == _PropertyFilter.commercial,
                                onTap: () => setState(() => _filter = _PropertyFilter.commercial),
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
                                    decoration: BoxDecoration(color: const Color(0xFFF3F4F1), shape: BoxShape.circle),
                                    child: Icon(PhosphorIcons.clipboardText(PhosphorIconsStyle.bold),
                                        size: 32, color: const Color(0xFF94A3B8)),
                                  ),
                                  const SizedBox(height: 16),
                                  Text('requirement_board_empty'.tr()),
                                ],
                              ),
                            ),
                          )
                        else
                          for (final requirement in filtered) ...[
                            _RequirementCard(
                              requirement: requirement,
                              onTap: () => context.push('/requirement-board/${requirement.requirementId}'),
                            ),
                            const SizedBox(height: 16),
                          ],
                      ],
                    ),
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

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, required this.selected, required this.onTap});

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

class _RequirementCard extends StatelessWidget {
  const _RequirementCard({required this.requirement, required this.onTap});

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
                      width: 72,
                      height: 72,
                      child: Consumer(
                        builder: (context, ref, _) => SignedPhoto(
                          path: requirement.photoUrls.first,
                          signedUrlFetcher: ref.read(requirementRepositoryProvider).createSignedUrl,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ] else ...[
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: const Color(0xFFF3F4F1), borderRadius: BorderRadius.circular(14)),
                    child: Icon(PhosphorIcons.buildings(PhosphorIconsStyle.bold), color: const Color(0xFF94A3B8)),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        RequirementFormatting.formatBudgetRange(
                          requirement.budgetMin,
                          requirement.budgetMax,
                          requirement.transactionType,
                        ),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${'listing_property_type_${requirement.propertyType}'.tr()} · '
                        '${'listing_transaction_type_${requirement.transactionType}'.tr()}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (requirement.bedrooms != null) ...[
                            Icon(PhosphorIcons.bed(PhosphorIconsStyle.bold), size: 15, color: const Color(0xFF5F5E5E)),
                            const SizedBox(width: 4),
                            Text('${requirement.bedrooms}', style: Theme.of(context).textTheme.labelSmall),
                            const SizedBox(width: 10),
                          ],
                          Icon(PhosphorIcons.mapPin(PhosphorIconsStyle.bold), size: 14, color: const Color(0xFF94A3B8)),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              requirement.area,
                              style: Theme.of(context).textTheme.labelSmall,
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
                      const SizedBox(height: 10),
                      Consumer(
                        builder: (context, ref, _) {
                          final ownerAsync = ref.watch(requirementOwnerProvider(requirement.negotiatorId));
                          return ownerAsync.when(
                            loading: () => const SizedBox.shrink(),
                            error: (error, stack) => const SizedBox.shrink(),
                            data: (owner) => Row(
                              children: [
                                NegotiatorAvatar(
                                  fullName: owner.fullName,
                                  avatarUrl: owner.avatarUrl,
                                  isOnline: owner.isOnline,
                                  size: 24,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    '${owner.fullName} (REN: ${owner.renNumber})',
                                    style: Theme.of(context).textTheme.labelSmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Spacer(),
                                Icon(PhosphorIcons.arrowRight(PhosphorIconsStyle.bold), size: 14, color: const Color(0xFF94A3B8)),
                              ],
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
