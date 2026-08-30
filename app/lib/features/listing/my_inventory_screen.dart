import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/brutalist_card.dart';
import 'listing_formatting.dart';
import 'listing_providers.dart';
import 'listing_status_filter.dart';

/// Ports stitch_renly_property_agent_network/my_inventory. Adds a third
/// "Withdrawn" tab beyond the mockup's Active/Sold -- the status model has
/// three states and hiding withdrawn listings from their own owner would
/// be a real gap, not a deliberate simplification.
class MyInventoryScreen extends ConsumerStatefulWidget {
  const MyInventoryScreen({super.key});

  @override
  ConsumerState<MyInventoryScreen> createState() => _MyInventoryScreenState();
}

class _MyInventoryScreenState extends ConsumerState<MyInventoryScreen> {
  String _selectedStatus = 'active';

  @override
  Widget build(BuildContext context) {
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text('inventory_title'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'active', label: Text('inventory_tab_active'.tr())),
                ButtonSegment(value: 'sold', label: Text('inventory_tab_sold'.tr())),
                ButtonSegment(value: 'withdrawn', label: Text('inventory_tab_withdrawn'.tr())),
              ],
              selected: {_selectedStatus},
              onSelectionChanged: (selection) => setState(() => _selectedStatus = selection.first),
            ),
          ),
          Expanded(
            // A null negotiatorId here is a brief startup race (the auth
            // redirect already guarantees a session reaches this route),
            // so it reads as "still loading", not as an error state.
            child: negotiatorId == null
                ? const Center(child: CircularProgressIndicator())
                : Consumer(
                    builder: (context, ref, _) {
                      final listingsAsync = ref.watch(myListingsProvider(negotiatorId));
                      return listingsAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
                        data: (listings) {
                          final filtered = ListingStatusFilter.byStatus(listings, _selectedStatus);
                          if (filtered.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'assets/illustrations/my_inventory_empty.png',
                                    height: 160,
                                    errorBuilder: (context, error, stackTrace) => const SizedBox(height: 160),
                                  ),
                                  const SizedBox(height: 16),
                                  Text('inventory_empty'.tr()),
                                ],
                              ),
                            );
                          }
                          return RefreshIndicator(
                            onRefresh: () async =>
                                ref.invalidate(myListingsProvider(negotiatorId)),
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final listing = filtered[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => context.push('/property/${listing.listingId}'),
                                      borderRadius: BorderRadius.circular(12),
                                      child: BrutalistCard(
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(listing.title),
                                          subtitle: Text(
                                            ListingFormatting.formatPrice(
                                                listing.price, listing.transactionType),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: BrutalistButton(
              label: 'inventory_post_new'.tr(),
              onPressed: () => context.push('/post-listing'),
            ),
          ),
        ],
      ),
    );
  }
}
