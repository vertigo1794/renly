import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/r_star_badge.dart';
import '../collaboration/cobroke_request_providers.dart' hide currentNegotiatorIdProvider;
import '../collaboration/send_cobroke_request_action.dart';
import '../listing/listing_formatting.dart';
import '../listing/listing_photo.dart';
import '../listing/listing_providers.dart';
import '../listing/models/listing.dart';
import '../matching/matching_providers.dart' hide currentNegotiatorIdProvider;
import '../matching/models/match_candidate.dart';
import '../notifications/notification_providers.dart';
import '../profile/profile_providers.dart' hide currentNegotiatorIdProvider;
import 'dashboard_formatting.dart';

/// Colors from the Stitch "Renly - Main Dashboard (Redesigned Premium)"
/// mockup's own Tailwind config that don't exist in the app-wide
/// [AppColors] palette. Scoped to this file only (a pixel-fidelity pass
/// requested for this one screen's body -- not promoted to a shared
/// token since no other screen uses this exact soft-card look).
class _MockColors {
  _MockColors._();
  static const surfaceMain = Color(0xFFF7F8F5);
  static const surfaceDark = Color(0xFF0D0E0B);
  static const surfaceMuted = Color(0xFFF0F2EB);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);
}

/// The Home branch's root screen in the bottom-nav shell. Restyled from
/// the Stitch "Renly - Main Dashboard (Redesigned Premium)" mockup
/// (docs/superpowers/specs/2026-09-06-renly-main-dashboard-redesign-design.md),
/// with a second pixel-fidelity pass on the body content (everything
/// below the brand header) matching the mockup's own soft/hard-card
/// visual language exactly, per direct request. The header row itself
/// (RStarBadge + wordmark + REN pill + bell) is untouched from the first
/// pass -- not part of this fidelity pass by explicit instruction.
class MainDashboardScreen extends ConsumerWidget {
  const MainDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final listingsAsync = ref.watch(marketplaceListingsProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);
    final myListingsAsync = negotiatorId == null
        ? const AsyncValue<List<Listing>>.data(<Listing>[])
        : ref.watch(myListingsProvider(negotiatorId));
    final receivedRequestsAsync = ref.watch(receivedRequestsProvider);
    final myMatchesAsync = ref.watch(myMatchesProvider);
    final marketPulseAsync =
        negotiatorId == null ? const AsyncValue.data(null) : ref.watch(marketPulseProvider(negotiatorId));

    return Scaffold(
      backgroundColor: _MockColors.surfaceMain,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Brand header row: wordmark + REN verification pill + bell.
              // Untouched by this pass -- do not restyle.
              Row(
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
              const SizedBox(height: 16),
              // Daily briefing: welcome text with the name underlined in
              // brand lime, per the mockup.
              profileAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (error, stack) => const SizedBox.shrink(),
                data: (profile) => RichText(
                  text: TextSpan(
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.0,
                        ),
                    children: [
                      TextSpan(text: '${'dashboard_welcome_back'.tr()} '),
                      TextSpan(
                        text: '${profile.fullName}.',
                        style: TextStyle(
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.primary,
                          decorationThickness: 3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'dashboard_subtitle'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _MockColors.slate600),
              ),
              // Market Pulse strip.
              marketPulseAsync.maybeWhen(
                data: (pulse) {
                  if (pulse == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: InkWell(
                      onTap: () => context.push('/my-matches'),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: _MockColors.surfaceDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'dashboard_market_pulse_live'.tr(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${pulse.count} ${'dashboard_market_pulse_new_matches'.tr()} ${pulse.area}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              'dashboard_market_pulse_view'.tr(),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                            ),
                            Icon(PhosphorIcons.caretRight(PhosphorIconsStyle.bold), color: AppColors.primary, size: 14),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 24),
              // Quick Actions grid.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'dashboard_quick_actions_title'.tr().toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.black54,
                          letterSpacing: 0.5,
                        ),
                  ),
                  Text(
                    'dashboard_quick_actions_hub'.tr(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _MockColors.slate400),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _QuickActionCard(
                        background: AppColors.primary,
                        onTap: () => context.push('/post-listing'),
                        iconCircleColor: Colors.black,
                        icon: PhosphorIcons.plus(PhosphorIconsStyle.bold),
                        iconColor: AppColors.primary,
                        tag: 'dashboard_quick_action_instant'.tr(),
                        tagBackground: Colors.black.withValues(alpha: 0.1),
                        tagColor: Colors.black,
                        title: 'dashboard_quick_action_post_listing'.tr(),
                        subtitle: 'dashboard_quick_action_post_listing_subtitle'.tr(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _QuickActionCard(
                        background: Colors.white,
                        onTap: () => context.go('/marketplace'),
                        iconCircleColor: _MockColors.surfaceMuted,
                        icon: PhosphorIcons.storefront(PhosphorIconsStyle.bold),
                        iconColor: Colors.black,
                        tag: listingsAsync.maybeWhen(
                          data: (listings) => listings.isEmpty
                              ? null
                              : '${listings.length} ${'dashboard_quick_action_market_active'.tr()}',
                          orElse: () => null,
                        ),
                        tagBackground: _MockColors.emerald100,
                        tagColor: _MockColors.emerald700,
                        title: 'dashboard_quick_action_market'.tr(),
                        subtitle: 'dashboard_quick_action_market_subtitle'.tr(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _MyInventoryCard(
                onTap: () => context.push('/my-inventory'),
                listingCount: myListingsAsync.maybeWhen(data: (listings) => listings.length, orElse: () => null),
                pendingCount: receivedRequestsAsync.maybeWhen(
                  data: (requests) => requests.where((c) => c.request.status == 'pending').length,
                  orElse: () => null,
                ),
              ),
              // Co-Broking Radar.
              myMatchesAsync.maybeWhen(
                data: (matches) {
                  final myListingMatches = negotiatorId == null
                      ? const <MatchCandidate>[]
                      : matches.where((c) => c.listing.negotiatorId == negotiatorId).toList();
                  if (myListingMatches.isEmpty) return const SizedBox.shrink();
                  final primary = myListingMatches.first;
                  final secondary = myListingMatches.skip(1).take(2).toList();
                  return Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'dashboard_radar_title'.tr(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.black),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  'dashboard_radar_subtitle'.tr(),
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _MockColors.slate500),
                                ),
                              ],
                            ),
                            InkWell(
                              onTap: () => context.push('/my-matches'),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${'dashboard_view_all'.tr()} (${myListingMatches.length})',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(fontWeight: FontWeight.bold, color: Colors.black),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(PhosphorIcons.caretRight(PhosphorIconsStyle.bold), size: 12),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _RadarPrimaryCard(
                          candidate: primary,
                          onCoBroke: () => sendCobrokeRequest(context, ref, primary.matchId),
                        ),
                        for (final candidate in secondary) ...[
                          const SizedBox(height: 10),
                          _RadarSecondaryRow(
                            candidate: candidate,
                            onTap: () => sendCobrokeRequest(context, ref, candidate.matchId),
                          ),
                        ],
                      ],
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 24),
              // Recent Listings.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'dashboard_recent_listings_title'.tr(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  InkWell(
                    onTap: () => context.go('/marketplace'),
                    child: Text(
                      'dashboard_view_all'.tr(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              listingsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stack) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('listing_error_generic'.tr())),
                ),
                data: (listings) {
                  if (listings.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('dashboard_recent_listings_empty'.tr())),
                    );
                  }
                  final recent = listings.take(10).toList();
                  return Column(
                    children: [
                      for (final listing in recent) ...[
                        _RecentListingRow(
                          listing: listing,
                          onTap: () => context.push('/property/${listing.listingId}'),
                        ),
                        if (listing != recent.last) const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One Quick Actions tile (Post Listing / Market) -- a bordered
/// hard-shadow card with an icon circle, an optional tag pill, and a
/// title/subtitle pair. [tag] is null (no pill rendered) rather than a
/// placeholder when the backing count isn't available yet -- matches
/// this screen's own no-fabricated-value convention.
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.background,
    required this.onTap,
    required this.iconCircleColor,
    required this.icon,
    required this.iconColor,
    required this.tag,
    required this.tagBackground,
    required this.tagColor,
    required this.title,
    required this.subtitle,
  });

  final Color background;
  final VoidCallback onTap;
  final Color iconCircleColor;
  final IconData icon;
  final Color iconColor;
  final String? tag;
  final Color tagBackground;
  final Color tagColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 112,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(3, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: iconCircleColor, shape: BoxShape.circle),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                if (tag != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(color: tagBackground, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      tag!,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: tagColor, fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: background == Colors.white ? _MockColors.slate500 : Colors.black.withValues(alpha: 0.75),
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The full-width "My Inventory" card. [listingCount]/[pendingCount] are
/// null (badge/subtext hidden entirely) rather than "0" while their
/// providers are loading/erroring, or when the real count is genuinely
/// zero -- this screen never shows a fabricated or placeholder count.
class _MyInventoryCard extends StatelessWidget {
  const _MyInventoryCard({required this.onTap, required this.listingCount, required this.pendingCount});

  final VoidCallback onTap;
  final int? listingCount;
  final int? pendingCount;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(3, 3))],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: _MockColors.surfaceDark, borderRadius: BorderRadius.circular(10)),
              child: Icon(PhosphorIcons.listBullets(PhosphorIconsStyle.bold), color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'dashboard_quick_action_my_inventory'.tr(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (listingCount != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _MockColors.slate100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _MockColors.slate200),
                          ),
                          child: Text(
                            '$listingCount ${'dashboard_quick_action_my_inventory_count'.tr()}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: _MockColors.slate700, fontWeight: FontWeight.bold, fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (pendingCount != null && pendingCount! > 0)
                    Text(
                      '$pendingCount ${'dashboard_quick_action_pending_requests'.tr()}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _MockColors.slate500),
                    ),
                ],
              ),
            ),
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(color: _MockColors.surfaceMuted, shape: BoxShape.circle),
              child: Icon(PhosphorIcons.caretRight(PhosphorIconsStyle.bold), size: 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Co-Broking Radar's primary (highest-score) match card: a photo
/// header with the match-score + a static "Exclusive" tag (decorative,
/// per an explicit direct request to match the mockup visually -- no
/// backing data claims anything about exclusivity), a static
/// "Standard Split" box (real per-match commission splits don't exist
/// until a CobrokeRequest becomes an Agreement), then price/location and
/// an agent footer with a real "Co-Broke" action.
class _RadarPrimaryCard extends StatelessWidget {
  const _RadarPrimaryCard({required this.candidate, required this.onCoBroke});

  final MatchCandidate candidate;
  final VoidCallback onCoBroke;

  @override
  Widget build(BuildContext context) {
    final listing = candidate.listing;
    final owner = candidate.requirementOwner;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(3, 3))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 144,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (listing.photoUrls.isNotEmpty)
                    ListingPhoto(path: listing.photoUrls.first, fit: BoxFit.cover)
                  else
                    Container(color: _MockColors.slate200),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black.withValues(alpha: 0.7), Colors.black.withValues(alpha: 0.05)],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            border: Border.all(color: Colors.black),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${candidate.score}% ${'dashboard_radar_match_percent'.tr()}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(fontWeight: FontWeight.w800, fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6)),
                          child: Text(
                            'dashboard_radar_exclusive'.tr(),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    left: 10,
                    right: 10,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'dashboard_radar_asking_price'.tr().toUpperCase(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: Colors.white70, fontSize: 9),
                              ),
                              Text(
                                ListingFormatting.formatPrice(listing.price, listing.transactionType),
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'dashboard_radar_split_label'.tr().toUpperCase(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: _MockColors.slate600, fontSize: 8),
                              ),
                              Text(
                                'dashboard_radar_split_value'.tr(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(fontWeight: FontWeight.w900, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.bedrooms != null
                        ? '${listing.title} • ${listing.bedrooms} ${'dashboard_radar_beds'.tr()}'
                        : listing.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(PhosphorIcons.mapPin(PhosphorIconsStyle.bold), size: 13, color: _MockColors.slate400),
                      const SizedBox(width: 4),
                      Text(
                        listing.area,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _MockColors.slate500),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, color: _MockColors.slate100),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: _MockColors.slate800,
                              child: Text(
                                owner.fullName.isNotEmpty ? owner.fullName[0].toUpperCase() : '?',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
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
                                      if (owner.agencyName != null) owner.agencyName!,
                                      'REN ${owner.renNumber}',
                                    ].join(' • '),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: _MockColors.slate500, fontSize: 10),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: onCoBroke,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'cobroke_request_send'.tr(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 4),
                              Icon(PhosphorIcons.arrowRight(PhosphorIconsStyle.bold), color: AppColors.primary, size: 14),
                            ],
                          ),
                        ),
                      ),
                    ],
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

/// A compact secondary Radar match row -- thin border (no hard shadow),
/// a thumbnail, a "New Demand" tag, and a quick chat-style action button.
class _RadarSecondaryRow extends StatelessWidget {
  const _RadarSecondaryRow({required this.candidate, required this.onTap});

  final MatchCandidate candidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final listing = candidate.listing;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 56,
              height: 56,
              child: listing.photoUrls.isNotEmpty
                  ? ListingPhoto(path: listing.photoUrls.first, fit: BoxFit.cover)
                  : Container(color: _MockColors.slate200),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'dashboard_radar_new_demand'.tr().toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800, fontSize: 8),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        listing.area,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(fontWeight: FontWeight.bold, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(
                  listing.title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  ListingFormatting.formatPrice(listing.price, listing.transactionType),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _MockColors.slate700, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _MockColors.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
              ),
              child: Icon(PhosphorIcons.chatCircle(PhosphorIconsStyle.bold), size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

/// A Recent Listings feed row: thumbnail (with a real, `status`-derived
/// pill -- never the mockup's fabricated "Open Co-Broke"/"Buyer Matched"
/// deal-progress labels, since this app has no per-listing deal-status
/// data to back those claims truthfully) and a real relative timestamp.
class _RecentListingRow extends StatelessWidget {
  const _RecentListingRow({required this.listing, required this.onTap});

  final Listing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.1), width: 2),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: listing.photoUrls.isNotEmpty
                        ? ListingPhoto(path: listing.photoUrls.first, fit: BoxFit.cover)
                        : Container(color: _MockColors.slate100),
                  ),
                ),
                if (listing.status == 'active')
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        'listing_status_available'.tr(),
                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (listing.status == 'active')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _MockColors.emerald50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'listing_status_available'.tr(),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: _MockColors.emerald600, fontWeight: FontWeight.bold, fontSize: 10),
                          ),
                        ),
                      Text(
                        DashboardFormatting.formatRelativeTime(listing.createdAt, DateTime.now()),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _MockColors.slate400, fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    listing.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    ListingFormatting.formatPrice(listing.price, listing.transactionType),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _MockColors.slate900,
                        ),
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
