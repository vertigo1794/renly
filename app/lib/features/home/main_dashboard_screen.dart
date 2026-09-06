import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/property_card.dart';
import '../../core/widgets/r_star_badge.dart';
import '../listing/listing_providers.dart';
import '../collaboration/cobroke_request_providers.dart' hide currentNegotiatorIdProvider;
import '../notifications/notification_providers.dart';
import '../profile/profile_providers.dart' hide currentNegotiatorIdProvider;

/// The Home branch's root screen in the bottom-nav shell. Restyled from
/// the Stitch "Renly - Main Dashboard (Redesigned Premium)" mockup
/// (docs/superpowers/specs/2026-09-06-renly-main-dashboard-redesign-design.md):
/// a custom brand header (not a standard AppBar -- the mockup's
/// left-aligned wordmark + right-aligned REN pill/bell doesn't fit a
/// centered-title AppBar), real count badges on the Quick Actions grid,
/// a Market Pulse strip and Co-Broking Radar section (both added by a
/// later task in the same plan), and a restyled Recent Listings feed.
class MainDashboardScreen extends ConsumerWidget {
  const MainDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final listingsAsync = ref.watch(marketplaceListingsProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);
    final myListingsAsync = negotiatorId == null
        ? const AsyncValue<List<dynamic>>.data([])
        : ref.watch(myListingsProvider(negotiatorId));
    final receivedRequestsAsync = ref.watch(receivedRequestsProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Brand header row: wordmark + REN verification pill + bell.
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
              profileAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (error, stack) => const SizedBox.shrink(),
                data: (profile) => Text(
                  '${'dashboard_welcome_back'.tr()} ${profile.fullName}.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: 4),
              Text('dashboard_subtitle'.tr()),
              // TASK 6: Market Pulse strip inserted here.
              const SizedBox(height: 24),
              Text('dashboard_quick_actions_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: BrutalistButton(
                        label: 'dashboard_quick_action_post_listing'.tr(),
                        icon: PhosphorIcons.plusCircle(PhosphorIconsStyle.bold),
                        onPressed: () => context.push('/post-listing'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: BrutalistButton(
                        label: listingsAsync.maybeWhen(
                          data: (listings) =>
                              '${'dashboard_quick_action_market'.tr()} · ${listings.length} ${'dashboard_quick_action_market_active'.tr()}',
                          orElse: () => 'dashboard_quick_action_market'.tr(),
                        ),
                        variant: BrutalistButtonVariant.secondary,
                        icon: PhosphorIcons.storefront(PhosphorIconsStyle.bold),
                        onPressed: () => context.go('/marketplace'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              BrutalistButton(
                label: myListingsAsync.maybeWhen(
                  data: (listings) =>
                      '${'dashboard_quick_action_my_inventory'.tr()} · ${listings.length} ${'dashboard_quick_action_my_inventory_count'.tr()}',
                  orElse: () => 'dashboard_quick_action_my_inventory'.tr(),
                ),
                variant: BrutalistButtonVariant.secondary,
                icon: PhosphorIcons.listBullets(PhosphorIconsStyle.bold),
                onPressed: () => context.push('/my-inventory'),
              ),
              receivedRequestsAsync.maybeWhen(
                data: (requests) {
                  final pending = requests.where((c) => c.request.status == 'pending').length;
                  if (pending == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      '$pending ${'dashboard_quick_action_pending_requests'.tr()}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              // TASK 6: Co-Broking Radar section inserted here.
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('dashboard_recent_listings_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
                  TextButton(
                    onPressed: () => context.go('/marketplace'),
                    child: Text('dashboard_view_all'.tr()),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: listingsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
                  data: (listings) {
                    if (listings.isEmpty) {
                      return Center(child: Text('dashboard_recent_listings_empty'.tr()));
                    }
                    final recent = listings.take(10).toList();
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: recent.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final listing = recent[index];
                        return SizedBox(
                          width: 260,
                          child: PropertyCard(
                            listing: listing,
                            onTap: () => context.push('/property/${listing.listingId}'),
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
      ),
    );
  }
}
