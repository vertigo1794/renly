import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
            child: negotiatorId == null
                ? const SizedBox.shrink()
                : Consumer(
                    builder: (context, ref, _) {
                      final listingsAsync = ref.watch(myListingsProvider(negotiatorId));
                      return listingsAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (error, stack) => Center(child: Text(error.toString())),
                        data: (listings) {
                          final filtered = ListingStatusFilter.byStatus(listings, _selectedStatus);
                          if (filtered.isEmpty) {
                            return Center(child: Text('inventory_empty'.tr()));
                          }
                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final listing = filtered[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                child: ListTile(
                                  onTap: () => context.push('/property/${listing.listingId}'),
                                  title: Text(listing.title),
                                  subtitle: Text(
                                    ListingFormatting.formatPrice(listing.price, listing.transactionType),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: ElevatedButton(
              onPressed: () => context.push('/post-listing'),
              child: Text('inventory_post_new'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}
