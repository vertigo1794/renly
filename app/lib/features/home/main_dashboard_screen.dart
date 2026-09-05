import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/property_card.dart';
import '../listing/listing_providers.dart';
import '../notifications/notification_providers.dart';
import '../profile/profile_providers.dart';

/// The Home branch's root screen in the bottom-nav shell (Task 8 wires this
/// in, replacing HomePlaceholderScreen). Shows a welcome header (negotiator's
/// name from myProfileProvider), quick-action shortcuts to the other tabs,
/// and a horizontal carousel of recent marketplace listings.
class MainDashboardScreen extends ConsumerWidget {
  const MainDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final listingsAsync = ref.watch(marketplaceListingsProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('app_name'.tr()),
        actions: [
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 24),
              Text('dashboard_quick_actions_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
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
                      label: 'dashboard_quick_action_market'.tr(),
                      variant: BrutalistButtonVariant.secondary,
                      icon: PhosphorIcons.storefront(PhosphorIconsStyle.bold),
                      onPressed: () => context.go('/marketplace'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              BrutalistButton(
                label: 'dashboard_quick_action_my_inventory'.tr(),
                variant: BrutalistButtonVariant.secondary,
                icon: PhosphorIcons.listBullets(PhosphorIconsStyle.bold),
                onPressed: () => context.push('/my-inventory'),
              ),
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
