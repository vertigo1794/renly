import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/r_star_badge.dart';
import '../collaboration/cobroke_request_providers.dart' hide currentNegotiatorIdProvider;
import '../collaboration/models/cobroke_request_candidate.dart';
import '../notifications/notification_providers.dart';
import '../profile/profile_providers.dart' hide currentNegotiatorIdProvider;
import 'listing_drafts_provider.dart';
import 'listing_providers.dart';
import 'listing_status_filter.dart';
import 'models/listing.dart';
import 'models/listing_draft.dart';

enum _InventoryTab { active, coBrokeReview, closedSold, drafts }

/// Restyled from the Stitch "My Inventory (Premium Co-Broking
/// Management)" mockup: a branded header (matching Dashboard/Marketplace/
/// Messages), a real live-stats ticker, 4 real tabs (Active/Co-Broke in
/// Review/Closed·Sold/Drafts -- the first 3 are a mutually-exclusive
/// partition via ListingStatusFilter.partition, Drafts is local-only),
/// and premium cards (added by a later task in the same plan -- see the
/// `// TASK 8:` marker below).
class MyInventoryScreen extends ConsumerStatefulWidget {
  const MyInventoryScreen({super.key});

  @override
  ConsumerState<MyInventoryScreen> createState() => _MyInventoryScreenState();
}

class _MyInventoryScreenState extends ConsumerState<MyInventoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _InventoryTab _tab = _InventoryTab.active;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Listing> _search(List<Listing> listings) {
    if (_query.trim().isEmpty) return listings;
    final q = _query.toLowerCase();
    return listings.where((l) => l.title.toLowerCase().contains(q) || l.area.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);
    final profileAsync = ref.watch(myProfileProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final receivedAsync = ref.watch(receivedRequestsProvider);
    final drafts = ref.watch(listingDraftsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAF7),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
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
                        final listingsAsync = ref.watch(myListingsProvider(negotiatorId));
                        return listingsAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
                          data: (listings) {
                            final received = receivedAsync.maybeWhen(
                              data: (r) => r,
                              orElse: () => const <CobrokeRequestCandidate>[],
                            );
                            final partition = ListingStatusFilter.partition(listings, received);
                            final pendingOnMyListings = received.where((c) => c.request.status == 'pending').length;

                            final visible = switch (_tab) {
                              _InventoryTab.active => _search(partition.active),
                              _InventoryTab.coBrokeReview => _search(partition.coBrokeInReview),
                              _InventoryTab.closedSold => _search(partition.closedSold),
                              _InventoryTab.drafts => const <Listing>[],
                            };

                            return RefreshIndicator(
                              onRefresh: () async {
                                ref.invalidate(myListingsProvider(negotiatorId));
                                ref.invalidate(receivedRequestsProvider);
                              },
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                'inventory_title'.tr(),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .headlineMedium
                                                    ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1.0),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                              decoration: BoxDecoration(
                                                  color: Colors.black, borderRadius: BorderRadius.circular(20)),
                                              child: Text(
                                                '${listings.length} ${'inventory_units_label'.tr()}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () => context.push('/post-listing'),
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            border: Border.all(color: Colors.black, width: 2),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(PhosphorIcons.plus(PhosphorIconsStyle.bold), size: 14),
                                              const SizedBox(width: 4),
                                              Text(
                                                'inventory_post_property'.tr(),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'inventory_subtitle'.tr(),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: const Color(0xFFE5E7EB)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: '$pendingOnMyListings ',
                                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                                TextSpan(text: 'inventory_ticker_inquiries'.tr()),
                                              ],
                                            ),
                                            style: Theme.of(context).textTheme.labelSmall,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => context.push('/my-requests'),
                                          child: Text(
                                            '${'inventory_ticker_review'.tr()} →',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextField(
                                    controller: _searchController,
                                    decoration: InputDecoration(
                                      hintText: 'inventory_search_hint'.tr(),
                                      prefixIcon: const Icon(Icons.search),
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
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
                                        _TabPill(
                                          label: '${'inventory_tab_active'.tr()} (${partition.active.length})',
                                          selected: _tab == _InventoryTab.active,
                                          onTap: () => setState(() => _tab = _InventoryTab.active),
                                        ),
                                        const SizedBox(width: 8),
                                        _TabPill(
                                          label:
                                              '${'inventory_tab_co_broke_review'.tr()} (${partition.coBrokeInReview.length})',
                                          selected: _tab == _InventoryTab.coBrokeReview,
                                          onTap: () => setState(() => _tab = _InventoryTab.coBrokeReview),
                                        ),
                                        const SizedBox(width: 8),
                                        _TabPill(
                                          label: '${'inventory_tab_closed_sold'.tr()} (${partition.closedSold.length})',
                                          selected: _tab == _InventoryTab.closedSold,
                                          onTap: () => setState(() => _tab = _InventoryTab.closedSold),
                                        ),
                                        const SizedBox(width: 8),
                                        _TabPill(
                                          label: 'inventory_tab_drafts'.tr(),
                                          selected: _tab == _InventoryTab.drafts,
                                          onTap: () => setState(() => _tab = _InventoryTab.drafts),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  if (_tab == _InventoryTab.drafts)
                                    if (drafts.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 60),
                                        child: Center(child: Text('inventory_drafts_empty'.tr())),
                                      )
                                    else
                                      for (final draft in drafts) ...[
                                        _DraftRow(draft: draft),
                                        const SizedBox(height: 10),
                                      ]
                                  else if (visible.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 60),
                                      child: Center(child: Text('inventory_empty'.tr())),
                                    )
                                  else
                                    // TASK 8: premium listing cards inserted here.
                                    for (final listing in visible) ...[
                                      Text(listing.title), // placeholder, replaced by Task 8
                                      const SizedBox(height: 10),
                                    ],
                                ],
                              ),
                            );
                          },
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.black : const Color(0xFFE5E7EB)),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected ? AppColors.primary : const Color(0xFF4B5563),
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
      ),
    );
  }
}

class _DraftRow extends ConsumerWidget {
  const _DraftRow({required this.draft});

  final ListingDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  draft.title.isEmpty ? '(untitled)' : draft.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  draft.price == null ? '' : 'RM ${draft.price}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(PhosphorIcons.trash(PhosphorIconsStyle.bold), size: 18),
            onPressed: () => ref.read(listingDraftsProvider.notifier).remove(draft.draftId),
          ),
          InkWell(
            onTap: () => GoRouter.of(context).push('/post-listing', extra: draft),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.primary,
                border: Border.all(color: Colors.black, width: 2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'inventory_resume_draft'.tr(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
