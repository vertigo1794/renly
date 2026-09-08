import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/negotiator_avatar.dart';
import '../../core/widgets/r_star_badge.dart';
import '../matching/matching_providers.dart' hide currentNegotiatorIdProvider;
import '../matching/models/match_candidate.dart';
import '../notifications/notification_providers.dart';
import '../profile/profile_providers.dart' hide currentNegotiatorIdProvider;
import 'broadcast_badge.dart';
import 'listing_formatting.dart';
import 'listing_photo.dart';
import 'listing_providers.dart';
import 'models/listing.dart';

enum _PropertyFilter { all, residential, commercial }

/// Restyled from the Stitch "Renly - Marketplace (Premium Co-Broking Hub)"
/// mockup: a branded header (matching MainDashboardScreen's own header
/// pattern), a real live-stats ticker, 3 real property-type filter pills
/// (the mockup's "New Demand"/"High Split" pills were dropped -- neither
/// has backing data: New Demand is a requirement-side concept, and every
/// listing shares the same static split value pre-agreement, so filtering
/// by it would be meaningless), and premium photo-header cards. Search is
/// still client-side only (filters the already-fetched active listings).
class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _PropertyFilter _filter = _PropertyFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Listing> _applyFilters(List<Listing> listings) {
    var result = listings;
    switch (_filter) {
      case _PropertyFilter.all:
        break;
      case _PropertyFilter.residential:
        result = result.where((l) => l.propertyType != 'commercial').toList();
      case _PropertyFilter.commercial:
        result = result.where((l) => l.propertyType == 'commercial').toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      result = result
          .where((l) =>
              l.title.toLowerCase().contains(q) ||
              l.area.toLowerCase().contains(q) ||
              l.state.toLowerCase().contains(q))
          .toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final listingsAsync = ref.watch(marketplaceListingsProvider);
    final profileAsync = ref.watch(myProfileProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final myMatchesAsync = ref.watch(myMatchesProvider);
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);

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
              child: listingsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
                data: (listings) {
                  final filtered = _applyFilters(listings);
                  final myListingMatches = negotiatorId == null
                      ? const <MatchCandidate>[]
                      : myMatchesAsync.maybeWhen(
                          data: (matches) =>
                              matches.where((c) => c.requirement.negotiatorId == negotiatorId).toList(),
                          orElse: () => const <MatchCandidate>[],
                        );

                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(marketplaceListingsProvider),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'marketplace_title'.tr(),
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                'marketplace_co_broke_tag'.tr(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'marketplace_subtitle'.tr(),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF5F5E5E)),
                        ),
                        const SizedBox(height: 14),
                        if (listings.isNotEmpty) _LiveTicker(listings: listings),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'marketplace_search_hint'.tr(),
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: const Color(0xFFE2E5DC)),
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
                                label: 'marketplace_filter_all'.tr(),
                                selected: _filter == _PropertyFilter.all,
                                onTap: () => setState(() => _filter = _PropertyFilter.all),
                              ),
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: 'marketplace_filter_residential'.tr(),
                                selected: _filter == _PropertyFilter.residential,
                                onTap: () => setState(() => _filter = _PropertyFilter.residential),
                              ),
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: 'marketplace_filter_commercial'.tr(),
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
                                  Image.asset(
                                    'assets/illustrations/marketplace_empty.png',
                                    height: 160,
                                    errorBuilder: (context, error, stackTrace) => const SizedBox(height: 160),
                                  ),
                                  const SizedBox(height: 16),
                                  Text('marketplace_empty'.tr()),
                                ],
                              ),
                            ),
                          )
                        else
                          ..._buildCards(context, filtered, myListingMatches),
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

  /// One card per listing, with the in-feed Co-Broke CTA banner inserted
  /// after the 2nd card (matching the mockup's placement) when there are
  /// at least 2 cards to insert it between.
  List<Widget> _buildCards(BuildContext context, List<Listing> filtered, List<MatchCandidate> myListingMatches) {
    final widgets = <Widget>[];
    for (var i = 0; i < filtered.length; i++) {
      final listing = filtered[i];
      final matchScore = myListingMatches
          .where((c) => c.listing.listingId == listing.listingId)
          .map((c) => c.score)
          .fold<int?>(null, (best, s) => best == null || s > best ? s : best);
      widgets.add(_MarketplaceCard(
        listing: listing,
        matchScore: matchScore,
        onTap: () => context.push('/property/${listing.listingId}'),
      ));
      if (i == 1) {
        widgets.add(const SizedBox(height: 16));
        widgets.add(_CoBrokeCtaBanner(onTap: () => context.push('/post-requirement')));
      }
      if (i != filtered.length - 1) {
        widgets.add(const SizedBox(height: 16));
      }
    }
    return widgets;
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

/// Real aggregate stats over the current active-listing feed -- no
/// area-scoping ("Klang Valley") or GDV terminology, since this app has
/// no per-region grouping and "total price sum" is the honest equivalent
/// of the mockup's GDV figure for what data actually exists.
class _LiveTicker extends StatelessWidget {
  const _LiveTicker({required this.listings});

  final List<Listing> listings;

  @override
  Widget build(BuildContext context) {
    final total = listings.fold<double>(0, (sum, l) => sum + l.price);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          BroadcastBadge(label: 'broadcast_live_badge'.tr(), color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${listings.length} ${'marketplace_ticker_active_units'.tr()} • ${ListingFormatting.formatPrice(total, 'sale')} ${'marketplace_ticker_total_value'.tr()}',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Icon(PhosphorIcons.lightning(PhosphorIconsStyle.fill), size: 14, color: AppColors.primary),
        ],
      ),
    );
  }
}

class _CoBrokeCtaBanner extends StatelessWidget {
  const _CoBrokeCtaBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Icon(PhosphorIcons.handshake(PhosphorIconsStyle.bold), color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'marketplace_cta_label'.tr().toUpperCase(),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold, letterSpacing: 0.6),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'marketplace_cta_title'.tr(),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'marketplace_cta_body'.tr(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'marketplace_cta_button'.tr(),
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    Icon(PhosphorIcons.arrowRight(PhosphorIconsStyle.bold), size: 16, color: AppColors.ink),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A premium marketplace card: photo header with a decorative category
/// badge and a static split badge (both purely visual, per direct
/// request -- no backing data claims either), a REAL match-score badge
/// shown only when this listing genuinely has a match against one of the
/// viewer's own requirements, price/specs/location, and an agent footer
/// with real owner data. Tapping the card OR its "Co-Broke" button both
/// open the property detail screen -- a per-card unconditional co-broke
/// action isn't possible (that requires a real Match's matchId, which
/// this feed doesn't always have), so the button defers to the detail
/// screen's own existing request flow rather than being disabled/hidden
/// on most cards.
/// One icon+label item inside the Beds/Baths/sqft stat row. Each present
/// stat gets equal width via the parent's Expanded+Center wrapper, so the
/// row stays balanced whether 1, 2, or 3 stats are present.
class _MarketplaceStatItem extends StatelessWidget {
  const _MarketplaceStatItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF5F5E5E)),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _MarketplaceCard extends StatelessWidget {
  const _MarketplaceCard({required this.listing, required this.matchScore, required this.onTap});

  final Listing listing;
  final int? matchScore;
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (listing.photoUrls.isNotEmpty)
                      ListingPhoto(path: listing.photoUrls.first, fit: BoxFit.cover)
                    else
                      Container(color: const Color(0xFFE2E8F0)),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (matchScore != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$matchScore% ${'marketplace_match_label'.tr()}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(fontWeight: FontWeight.w900, fontSize: 10),
                              ),
                            ),
                          if (listing.titleVerified || listing.exclusiveMandate) ...[
                            if (matchScore != null) const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (listing.titleVerified)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration:
                                        BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(6)),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.bold), size: 12, color: Colors.white),
                                        const SizedBox(width: 4),
                                        Text(
                                          'inventory_badge_title_verified'.tr(),
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (listing.exclusiveMandate)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration:
                                        BoxDecoration(color: const Color(0xFF7C3AED), borderRadius: BorderRadius.circular(6)),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(PhosphorIcons.crown(PhosphorIconsStyle.bold), size: 12, color: Colors.white),
                                        const SizedBox(width: 4),
                                        Text(
                                          'inventory_badge_exclusive_mandate'.tr(),
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
                        ),
                        child: Text(
                          'marketplace_split_static'.tr(),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900, fontSize: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('RM', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      Text(
                        ListingFormatting.formatPrice(listing.price, listing.transactionType).replaceFirst('RM ', ''),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    listing.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(PhosphorIcons.mapPin(PhosphorIconsStyle.bold), size: 13, color: const Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${listing.area}, ${listing.state}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF64748B)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Builder(builder: (context) {
                    final stats = <Widget>[
                      if (listing.bedrooms != null)
                        _MarketplaceStatItem(
                          icon: PhosphorIcons.bed(PhosphorIconsStyle.bold),
                          text: '${listing.bedrooms} ${'marketplace_beds'.tr()}',
                        ),
                      if (listing.bathrooms != null)
                        _MarketplaceStatItem(
                          icon: PhosphorIcons.bathtub(PhosphorIconsStyle.bold),
                          text: '${listing.bathrooms} ${'marketplace_baths'.tr()}',
                        ),
                      if (listing.builtUpSqft != null)
                        _MarketplaceStatItem(
                          icon: PhosphorIcons.ruler(PhosphorIconsStyle.bold),
                          text: '${ListingFormatting.formatSqft(listing.builtUpSqft!)} ${'inventory_stat_sqft'.tr()}',
                        ),
                    ];
                    if (stats.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          for (var i = 0; i < stats.length; i++) Expanded(child: Center(child: stats[i])),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 1, color: Color(0xFFE2E5DC)),
                  const SizedBox(height: 10),
                  Consumer(
                    builder: (context, ref, _) {
                      final ownerAsync = ref.watch(listingOwnerProvider(listing.negotiatorId));
                      return Row(
                        children: [
                          Expanded(
                            child: ownerAsync.when(
                              loading: () => const SizedBox.shrink(),
                              error: (error, stack) => const SizedBox.shrink(),
                              data: (owner) => Row(
                                children: [
                                  NegotiatorAvatar(
                                    fullName: owner.fullName,
                                    avatarUrl: owner.avatarUrl,
                                    isOnline: owner.isOnline,
                                    size: 30,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          owner.fullName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(fontWeight: FontWeight.bold),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          [
                                            'REN ${owner.renNumber}',
                                            if (owner.agencyName != null) owner.agencyName!,
                                          ].join(' • '),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(color: const Color(0xFF64748B), fontSize: 10),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: onTap,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'cobroke_request_send'.tr(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(PhosphorIcons.arrowRight(PhosphorIconsStyle.bold), size: 13, color: Colors.white),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
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
