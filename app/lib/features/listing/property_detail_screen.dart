// app/lib/features/listing/property_detail_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'listing_formatting.dart';
import 'listing_photo.dart';
import 'listing_providers.dart';
import 'models/listing.dart';

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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('listing_error_generic'.tr())),
        );
      }
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
                    OutlinedButton(
                      onPressed: () => context.push('/property/${widget.listingId}/matches'),
                      child: Text('matching_view_matches'.tr()),
                    ),
                    const SizedBox(height: 8),
                    if (listing.status != 'sold')
                      OutlinedButton(
                        onPressed: () => _changeStatus(listing, 'sold'),
                        child: Text('property_mark_sold'.tr()),
                      ),
                    if (listing.status != 'withdrawn')
                      OutlinedButton(
                        onPressed: () => _changeStatus(listing, 'withdrawn'),
                        child: Text('property_withdraw'.tr()),
                      ),
                    if (listing.status != 'active')
                      OutlinedButton(
                        onPressed: () => _changeStatus(listing, 'active'),
                        child: Text('property_reactivate'.tr()),
                      ),
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
