// app/lib/features/listing/property_detail_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'listing_formatting.dart';
import 'listing_providers.dart';
import 'models/listing_owner.dart';

/// Ports stitch_renly_property_agent_network/property_detail.
class PropertyDetailScreen extends ConsumerStatefulWidget {
  const PropertyDetailScreen({super.key, required this.listingId});

  final String listingId;

  @override
  ConsumerState<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends ConsumerState<PropertyDetailScreen> {
  Future<void> _changeStatus(String status) async {
    final repository = ref.read(listingRepositoryProvider);
    await repository.updateListingStatus(listingId: widget.listingId, status: status);
    ref.invalidate(listingDetailProvider(widget.listingId));
  }

  @override
  Widget build(BuildContext context) {
    final listingAsync = ref.watch(listingDetailProvider(widget.listingId));
    final currentNegotiatorId = ref.watch(currentNegotiatorIdProvider);

    return Scaffold(
      body: listingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text(error.toString())),
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
                          for (final _ in listing.photoUrls)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16),
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
                  Text(listing.area, style: Theme.of(context).textTheme.bodyMedium),
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
                    if (listing.status != 'sold')
                      OutlinedButton(
                        onPressed: () => _changeStatus('sold'),
                        child: Text('property_mark_sold'.tr()),
                      ),
                    if (listing.status != 'withdrawn')
                      OutlinedButton(
                        onPressed: () => _changeStatus('withdrawn'),
                        child: Text('property_withdraw'.tr()),
                      ),
                    if (listing.status != 'active')
                      OutlinedButton(
                        onPressed: () => _changeStatus('active'),
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
