// app/lib/features/listing/property_detail_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'listing_formatting.dart';
import 'listing_photo.dart';
import 'listing_providers.dart';
import 'models/listing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/status_badge.dart';
import '../collaboration/cobroke_request_providers.dart' hide currentNegotiatorIdProvider;
import '../collaboration/models/cobroke_request_candidate.dart';
import '../collaboration/send_cobroke_request_action.dart';
import '../matching/live_match_preview.dart';
import '../matching/matching_providers.dart' hide currentNegotiatorIdProvider;
import '../matching/models/match_candidate.dart';
import '../ratings/rating_providers.dart' hide currentNegotiatorIdProvider;
import '../requirement/requirement_providers.dart' hide currentNegotiatorIdProvider;
import '../subscription/subscription_providers.dart' hide currentNegotiatorIdProvider;

/// Ports stitch_renly_property_agent_network/property_detail.
class PropertyDetailScreen extends ConsumerStatefulWidget {
  const PropertyDetailScreen({super.key, required this.listingId});

  final String listingId;

  @override
  ConsumerState<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends ConsumerState<PropertyDetailScreen> {
  int? _bestMatchScore;

  @override
  void initState() {
    super.initState();
    _loadBestMatchScore();
  }

  /// Best-effort, same reasoning as every other live-preview fetch this
  /// session: the hero match badge is a real enhancement, never a
  /// requirement for the screen to render. A failure here (offline,
  /// backend hiccup, or an uninitialized Supabase client in tests) must
  /// not crash the screen; `_bestMatchScore` simply stays null and the
  /// badge's own null-check keeps it hidden.
  Future<void> _loadBestMatchScore() async {
    final viewerId = ref.read(currentNegotiatorIdProvider);
    if (viewerId == null) return;
    try {
      final listing = await ref.read(listingRepositoryProvider).fetchListingById(widget.listingId);
      if (listing.negotiatorId == viewerId) return; // never score your own listing
      final ownRequirements = await ref.read(requirementRepositoryProvider).fetchOwnRequirements(viewerId);
      final score = LiveMatchPreview.bestScoreForListing(listing, ownRequirements);
      if (!mounted) return;
      setState(() => _bestMatchScore = score);
    } catch (e) {
      debugPrint('_loadBestMatchScore failed: $e');
    }
  }

  /// Takes the listing (not just the new status) so the two list providers
  /// can be invalidated too -- otherwise a listing marked sold here stays
  /// in the marketplace and in My Inventory's Active tab until restart.
  Future<void> _changeStatus(Listing listing, String status) async {
    final repository = ref.read(listingRepositoryProvider);
    try {
      await repository.updateListingStatus(listingId: widget.listingId, status: status);
      ref.invalidate(listingDetailProvider(widget.listingId));
      ref.invalidate(marketplaceListingsProvider);
      ref.invalidate(myListingsProvider(listing.negotiatorId));
      // The cap counter is not autoDispose, so withdrawing/reactivating here
      // must invalidate it too -- otherwise a free-tier user who withdraws a
      // listing to free up a slot still sees PostListingFormBody's submit
      // button disabled with the upsell message, with no in-app way to
      // clear it.
      ref.invalidate(activeListingCountProvider(listing.negotiatorId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('listing_error_generic'.tr())),
        );
      }
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'inventory_tab_active'.tr();
      case 'sold':
        return 'inventory_tab_sold'.tr();
      default:
        return 'inventory_tab_withdrawn'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    final listingAsync = ref.watch(listingDetailProvider(widget.listingId));
    final currentNegotiatorId = ref.watch(currentNegotiatorIdProvider);

    return Scaffold(
      appBar: AppBar(),
      body: listingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
        data: (listing) {
          final isOwner = currentNegotiatorId != null && currentNegotiatorId == listing.negotiatorId;
          // Only watched for the owner: the cap-gated reactivate button below
          // renders inside `if (isOwner)`, and subscriptionStatusProvider is a
          // live Realtime subscription. Watching it unconditionally would open
          // (and tear down) a channel for every non-owner browsing a listing,
          // which is the common case.
          var atCap = false;
          if (isOwner) {
            final tierAsync = ref.watch(subscriptionStatusProvider);
            final countAsync = ref.watch(activeListingCountProvider(currentNegotiatorId));
            atCap = tierAsync.valueOrNull?.tier == 'free' && (countAsync.valueOrNull ?? 0) >= 3;
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeroHeader(
                    listing: listing,
                    bestMatchScore: _bestMatchScore,
                  ),
                  const SizedBox(height: 16),
                  _DealTermsBanner(listing: listing),
                  const SizedBox(height: 16),
                  _OverviewCard(listing: listing, statusLabel: _statusLabel(listing.status)),
                  const SizedBox(height: 16),
                  _CoBrokingTermsCard(listing: listing),
                  const SizedBox(height: 16),
                  _AgentCard(listingId: listing.listingId, negotiatorId: listing.negotiatorId),
                  const SizedBox(height: 16),
                  _ActionBar(
                    listing: listing,
                    isOwner: isOwner,
                    atCap: atCap,
                    onMarkSold: () => _changeStatus(listing, 'sold'),
                    onWithdraw: () => _changeStatus(listing, 'withdrawn'),
                    onReactivate: () => _changeStatus(listing, 'active'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeroHeader extends StatefulWidget {
  const _HeroHeader({required this.listing, required this.bestMatchScore});

  final Listing listing;
  final int? bestMatchScore;

  @override
  State<_HeroHeader> createState() => _HeroHeaderState();
}

class _HeroHeaderState extends State<_HeroHeader> {
  final _pageController = PageController();
  // 0-based internally (matches PageView/PageController); the counter pill
  // displays this +1 so a freshly-opened listing reads "1/N", not "0/N".
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final bestMatchScore = widget.bestMatchScore;
    final hasPhotos = listing.photoUrls.isNotEmpty;
    final hasBadges = bestMatchScore != null || listing.exclusiveMandate;
    // Bug fix vs. the original draft: an unconditional `if (photoUrls.isEmpty)
    // return SizedBox.shrink()` here would also swallow the match badge and
    // exclusive-mandate badge for any photo-less listing (the common case in
    // this project's own test fixtures) -- those badges carry real signal
    // independent of whether photos were uploaded, so only the photo
    // carousel and photo counter (which have nothing to show without
    // photos) are gated on `hasPhotos`.
    if (!hasPhotos && !hasBadges) return const SizedBox.shrink();
    return SizedBox(
      height: 260,
      child: Stack(
        children: [
          if (!hasPhotos)
            Positioned.fill(
              child: Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Center(
                  child: Icon(
                    PhosphorIcons.buildingApartment(PhosphorIconsStyle.light),
                    size: 72,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          if (hasPhotos)
            Positioned.fill(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: [
                  for (final photoPath in listing.photoUrls)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: ListingPhoto(path: photoPath),
                      ),
                    ),
                ],
              ),
            ),
          Positioned(
            top: 12,
            left: 12,
            child: Wrap(
              spacing: 6,
              children: [
                if (bestMatchScore != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.black),
                    ),
                    child: Text(
                      'property_match_badge'.tr(namedArgs: {'score': '$bestMatchScore'}),
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11),
                    ),
                  ),
                if (listing.exclusiveMandate)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      'inventory_badge_exclusive_mandate'.tr(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          if (hasPhotos)
            Positioned(
              bottom: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  // Defensive clamp: not reachable today (PageView only ever
                  // reports indices within photoUrls' own range via
                  // onPageChanged), but guards against a future off-by-one
                  // or a stale _currentPage surviving a photoUrls change.
                  'property_photo_counter'.tr(
                    namedArgs: {
                      'current': '${(_currentPage + 1).clamp(1, listing.photoUrls.length)}',
                      'total': '${listing.photoUrls.length}',
                    },
                  ),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DealTermsBanner extends StatelessWidget {
  const _DealTermsBanner({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final pricePerSqft = listing.builtUpSqft != null && listing.builtUpSqft! > 0
        ? (listing.price / listing.builtUpSqft!).round()
        : null;
    // Rounded to the SAME integer percent shown in the "X/Y" ratio right
    // below -- _CoBrokingTermsCard computes its own "your share" RM figure
    // off this identical rounded int (see _CoBrokingTermsCard.build), so a
    // fractional split (e.g. 52.5, reachable via the free-text Custom
    // field) can never show two different RM amounts for what both cards
    // present as the same fact.
    final splitRounded = listing.commissionSplitPercent?.round();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (listing.commissionSplitPercent != null) ...[
            Row(
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(
                  'property_co_broke_ready'.tr(),
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 11),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 20),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ListingFormatting.formatPrice(listing.price, listing.transactionType),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24),
                    ),
                    if (pricePerSqft != null || listing.maintenanceFeeMyr != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (pricePerSqft != null) 'property_price_per_sqft'.tr(namedArgs: {'value': '$pricePerSqft'}),
                          if (listing.maintenanceFeeMyr != null)
                            'property_maintenance_suffix'.tr(namedArgs: {'value': '${listing.maintenanceFeeMyr!.round()}'}),
                        ].join(' • '),
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              if (splitRounded != null)
                Container(
                  key: const Key('deal_terms_split_badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$splitRounded/${100 - splitRounded}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                      Text(
                        'RM ${(listing.price * splitRounded / 100).round()}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
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

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.listing, required this.statusLabel});

  final Listing listing;
  final String statusLabel;

  Future<void> _openMap(BuildContext context) async {
    final query = Uri.encodeComponent('${listing.area}, ${listing.state}');
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('listing_error_generic'.tr())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortId = listing.listingId.length >= 8 ? listing.listingId.substring(0, 8).toUpperCase() : listing.listingId.toUpperCase();
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Text(
                    listing.tenure == null ? listing.propertyType.toUpperCase() : '${listing.propertyType.toUpperCase()} • ${listing.tenure!.toUpperCase()}',
                    style: const TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.bold, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'property_id_prefix'.tr(namedArgs: {'id': shortId}),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(listing.title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('${listing.area}, ${listing.state}', style: Theme.of(context).textTheme.bodyMedium),
              ),
              TextButton(
                onPressed: () => _openMap(context),
                child: Text('property_map_button'.tr()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusBadge(label: statusLabel),
              if (listing.titleVerified)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.bold), size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'inventory_badge_title_verified'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              if (listing.keysOnHand)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIcons.key(PhosphorIconsStyle.bold), size: 12, color: const Color(0xFF2563EB)),
                      const SizedBox(width: 4),
                      Text(
                        'property_badge_keys_on_hand'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              if (listing.protectedCoBrokeReg)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIcons.lockKey(PhosphorIconsStyle.bold), size: 12, color: const Color(0xFF7C3AED)),
                      const SizedBox(width: 4),
                      Text(
                        'property_badge_protected_co_broke_reg'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Wrap, not a plain Row: up to 6 stat items (5 numeric specs plus
          // furnishing) can't all fit one line at phone width once 3+
          // optional fields are populated -- items that don't fit flow to
          // a second line instead of forcing a RenderFlex overflow, per
          // this card's own original "bento grid" intent.
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (listing.bedrooms != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bed),
                    const SizedBox(width: 4),
                    Text('${listing.bedrooms}'),
                  ],
                ),
              if (listing.bathrooms != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bathtub),
                    const SizedBox(width: 4),
                    Text('${listing.bathrooms}'),
                  ],
                ),
              if (listing.builtUpSqft != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIcons.ruler(PhosphorIconsStyle.bold)),
                    const SizedBox(width: 4),
                    Text('${ListingFormatting.formatSqft(listing.builtUpSqft!)} ${'inventory_stat_sqft'.tr()}'),
                  ],
                ),
              if (listing.parkingBays != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIcons.car(PhosphorIconsStyle.bold)),
                    const SizedBox(width: 4),
                    Text('${listing.parkingBays}'),
                  ],
                ),
              if (listing.floorLevel != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIcons.stackSimple(PhosphorIconsStyle.bold)),
                    const SizedBox(width: 4),
                    Text('${listing.floorLevel}'),
                  ],
                ),
              if (listing.furnishingStatus != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIcons.armchair(PhosphorIconsStyle.bold)),
                    const SizedBox(width: 4),
                    Text(listing.furnishingStatus == 'furnished'
                        ? 'listing_furnishing_furnished'.tr()
                        : listing.furnishingStatus == 'partially_furnished'
                            ? 'listing_furnishing_partially_furnished'.tr()
                            : 'listing_furnishing_unfurnished'.tr()),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('property_overview'.tr(), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(listing.description, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _CoBrokingTermsCard extends StatelessWidget {
  const _CoBrokingTermsCard({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    if (listing.commissionSplitPercent == null && listing.totalAgencyCommissionPercent == null) {
      return const SizedBox.shrink();
    }
    final split = listing.commissionSplitPercent?.round();
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    Icon(PhosphorIcons.handshake(PhosphorIconsStyle.bold), size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'property_co_broking_terms_title'.tr(),
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (split != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.black)),
                  child: Text(
                    'property_split_badge'.tr(namedArgs: {'split': '$split/${100 - split}'}),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF7F8F5), borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                if (listing.totalAgencyCommissionPercent != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'property_total_commission_row'.tr(namedArgs: {'percent': '${listing.totalAgencyCommissionPercent!.round()}'}),
                            style: Theme.of(context).textTheme.labelSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'RM ${(listing.price * listing.totalAgencyCommissionPercent! / 100).round()}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                if (split != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'property_your_share_row'.tr(namedArgs: {'percent': '$split'}),
                          style: Theme.of(context).textTheme.labelSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'RM ${(listing.price * split / 100).round()}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF047857)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(PhosphorIcons.shieldCheck(PhosphorIconsStyle.bold), size: 13, color: const Color(0xFF047857)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'property_registration_guarantee'.tr(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF64748B)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgentCard extends ConsumerWidget {
  const _AgentCard({required this.listingId, required this.negotiatorId});

  final String listingId;
  final String negotiatorId;

  /// Plain-loop equivalent of `.firstWhereOrNull` -- avoids adding the
  /// `collection` package as a new direct dependency for one call site
  /// (it's currently only a transitive dependency via pubspec.lock).
  static CobrokeRequestCandidate? _acceptedRequestForThisListing(List<CobrokeRequestCandidate> candidates, String listingId) {
    for (final candidate in candidates) {
      if (candidate.match.listing.listingId == listingId && candidate.request.status == 'accepted') {
        return candidate;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownerAsync = ref.watch(listingOwnerProvider(negotiatorId));
    final ratingsAsync = ref.watch(ratingsForNegotiatorProvider(negotiatorId));
    final sentAsync = ref.watch(sentRequestsProvider);
    final receivedAsync = ref.watch(receivedRequestsProvider);
    final acceptedCandidate = _acceptedRequestForThisListing(
      [...?sentAsync.valueOrNull, ...?receivedAsync.valueOrNull],
      listingId,
    );

    return ownerAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (owner) {
        // Real, non-empty candidate list only -- per the design doc, a
        // negotiator with no ratings yet (or whose ratings are still
        // loading) shows NO rating row at all, never a fabricated "New
        // Agent" placeholder standing in for a real average.
        final ratings = ratingsAsync.valueOrNull;
        final hasRatings = ratings != null && ratings.isNotEmpty;
        final ratingText = hasRatings
            ? '${(ratings.map((c) => c.rating.stars).reduce((a, b) => a + b) / ratings.length).toStringAsFixed(1)} (${ratings.length})'
            : null;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: Row(
            children: [
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
                    if (hasRatings) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(PhosphorIcons.star(PhosphorIconsStyle.fill), size: 13, color: const Color(0xFFF59E0B)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              ratingText!,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: acceptedCandidate == null
                    ? null
                    : () => context.push('/messages/${acceptedCandidate.request.requestId}'),
                icon: Icon(PhosphorIcons.chatCircle(PhosphorIconsStyle.bold), size: 16),
                label: Text('property_message_button'.tr()),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionBar extends ConsumerWidget {
  const _ActionBar({
    required this.listing,
    required this.isOwner,
    required this.atCap,
    required this.onMarkSold,
    required this.onWithdraw,
    required this.onReactivate,
  });

  final Listing listing;
  final bool isOwner;
  final bool atCap;
  final VoidCallback onMarkSold;
  final VoidCallback onWithdraw;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isOwner) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutalistButton(
            label: 'matching_view_matches'.tr(),
            onPressed: () => context.push('/property/${listing.listingId}/matches'),
            variant: BrutalistButtonVariant.secondary,
          ),
          const SizedBox(height: 8),
          if (listing.status != 'sold') ...[
            BrutalistButton(
              label: 'property_mark_sold'.tr(),
              onPressed: onMarkSold,
              variant: BrutalistButtonVariant.secondary,
            ),
            const SizedBox(height: 8),
          ],
          if (listing.status != 'withdrawn') ...[
            BrutalistButton(
              label: 'property_withdraw'.tr(),
              onPressed: onWithdraw,
              variant: BrutalistButtonVariant.secondary,
            ),
            const SizedBox(height: 8),
          ],
          if (listing.status != 'active') ...[
            if (atCap) ...[
              Text(
                'listing_cap_reached_message'.tr(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            BrutalistButton(
              label: 'property_reactivate'.tr(),
              onPressed: atCap ? null : onReactivate,
              variant: BrutalistButtonVariant.secondary,
            ),
          ],
        ],
      );
    }

    final viewerId = ref.watch(currentNegotiatorIdProvider);
    final matchesAsync = viewerId == null
        ? const AsyncValue<List<MatchCandidate>>.data([])
        : ref.watch(matchesForListingProvider(listing.listingId));
    MatchCandidate? ownMatch;
    for (final candidate in matchesAsync.valueOrNull ?? const <MatchCandidate>[]) {
      if (candidate.requirement.negotiatorId == viewerId) {
        ownMatch = candidate;
        break;
      }
    }

    return Row(
      children: [
        // Deliberately tight (default OutlinedButton padding/min-size claims
        // much more width than this icon+label content needs) -- the CTA
        // beside it is the primary action and needs the room; this button
        // is secondary and only needs to fit "Client".
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => SharePlus.instance.share(
            ShareParams(text: '${listing.title} - ${ListingFormatting.formatPrice(listing.price, listing.transactionType)} - ${listing.area}, ${listing.state}'),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIcons.paperPlaneTilt(PhosphorIconsStyle.bold), size: 20),
              Text('property_client_share_label'.tr(), style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Tooltip(
            message: ownMatch == null ? 'property_request_co_broke_disabled_reason'.tr() : '',
            // A smaller labelLarge for this specific placement, on top of
            // the width freed up from the Client button above -- this slot
            // next to a second button is tighter than every other
            // (full-width) place BrutalistButton is used. BrutalistButton
            // itself now wraps its label in Flexible+ellipsis, so a genuine
            // width shortfall here truncates instead of throwing a
            // RenderFlex overflow. This button's own leading arrow icon was
            // removed (it was decorative, not load-bearing information) and
            // the font size dropped from 16 to 12.5 -- at 13 the label still
            // fell 0.2px short of the available width at 360dp (measured
            // empirically), so 12.5 was chosen to clear it with real margin,
            // not just barely. Verified at 360dp in both "Request Co-Broke"
            // (en) and "Minta Co-Broke" (ms) that the label now renders in
            // full; see property_detail_screen_test.dart's two
            // "does not ellipsize the Request Co-Broke label" tests. A
            // future translation meaningfully longer than either could still
            // ellipsize -- that's an accepted, graceful fallback (thanks to
            // BrutalistButton's own fix), not a bug.
            child: Theme(
              data: Theme.of(context).copyWith(
                textTheme: Theme.of(context).textTheme.copyWith(
                      labelLarge: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 12.5),
                    ),
              ),
              child: BrutalistButton(
                label: 'cobroke_request_send'.tr(),
                onPressed: ownMatch == null ? null : () => sendCobrokeRequest(context, ref, ownMatch!.matchId),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
