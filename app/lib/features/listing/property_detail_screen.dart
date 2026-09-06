// app/lib/features/listing/property_detail_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'listing_formatting.dart';
import 'listing_photo.dart';
import 'listing_providers.dart';
import 'models/listing.dart';
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/status_badge.dart';
import '../subscription/subscription_providers.dart' hide currentNegotiatorIdProvider;

/// Ports stitch_renly_property_agent_network/property_detail.
class PropertyDetailScreen extends ConsumerStatefulWidget {
  const PropertyDetailScreen({super.key, required this.listingId});

  final String listingId;

  @override
  ConsumerState<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends ConsumerState<PropertyDetailScreen> {
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
                  if (listing.photoUrls.isNotEmpty)
                    SizedBox(
                      height: 220,
                      child: PageView(
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
                  const SizedBox(height: 16),
                  Text(listing.title, style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StatusBadge(label: _statusLabel(listing.status)),
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
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      if (listing.exclusiveMandate)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFF7C3AED), borderRadius: BorderRadius.circular(6)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(PhosphorIcons.crown(PhosphorIconsStyle.bold), size: 12, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                'inventory_badge_exclusive_mandate'.tr(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ListingFormatting.formatPrice(listing.price, listing.transactionType),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (listing.bedrooms != null) ...[
                        const Icon(Icons.bed),
                        const SizedBox(width: 4),
                        Text('${listing.bedrooms}'),
                        const SizedBox(width: 16),
                      ],
                      if (listing.bathrooms != null) ...[
                        const Icon(Icons.bathtub),
                        const SizedBox(width: 4),
                        Text('${listing.bathrooms}'),
                        if (listing.builtUpSqft != null) const SizedBox(width: 16),
                      ],
                      if (listing.builtUpSqft != null) ...[
                        Icon(PhosphorIcons.ruler(PhosphorIconsStyle.bold)),
                        const SizedBox(width: 4),
                        Text('${ListingFormatting.formatSqft(listing.builtUpSqft!)} ${'inventory_stat_sqft'.tr()}'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('property_overview'.tr(), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(listing.description, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  Text('property_location'.tr(), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('${listing.area}, ${listing.state}',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  Builder(builder: (context) {
                    final ownerAsync = ref.watch(listingOwnerProvider(listing.negotiatorId));
                    return ownerAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (error, stack) => const SizedBox.shrink(),
                      data: (owner) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(owner.fullName, style: Theme.of(context).textTheme.titleMedium),
                          Text('REN: ${owner.renNumber}', style: Theme.of(context).textTheme.labelSmall),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                  if (isOwner) ...[
                    BrutalistButton(
                      label: 'matching_view_matches'.tr(),
                      onPressed: () => context.push('/property/${widget.listingId}/matches'),
                      variant: BrutalistButtonVariant.secondary,
                    ),
                    const SizedBox(height: 8),
                    if (listing.status != 'sold') ...[
                      BrutalistButton(
                        label: 'property_mark_sold'.tr(),
                        onPressed: () => _changeStatus(listing, 'sold'),
                        variant: BrutalistButtonVariant.secondary,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (listing.status != 'withdrawn') ...[
                      BrutalistButton(
                        label: 'property_withdraw'.tr(),
                        onPressed: () => _changeStatus(listing, 'withdrawn'),
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
                        onPressed: atCap ? null : () => _changeStatus(listing, 'active'),
                        variant: BrutalistButtonVariant.secondary,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
