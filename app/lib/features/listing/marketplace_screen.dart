import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/property_card.dart';
import 'listing_providers.dart';
import 'models/listing.dart';

/// Ports stitch_renly_property_agent_network/marketplace. Search is
/// client-side only for this pass (filters the already-fetched active
/// listings) -- no server-side full-text search yet.
class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Listing> _filter(List<Listing> listings) {
    if (_query.trim().isEmpty) return listings;
    final q = _query.toLowerCase();
    return listings
        .where((l) =>
            l.title.toLowerCase().contains(q) ||
            l.area.toLowerCase().contains(q) ||
            l.state.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final listingsAsync = ref.watch(marketplaceListingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('marketplace_title'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'marketplace_search_hint'.tr(),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: listingsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
              data: (listings) {
                final filtered = _filter(listings);
                if (filtered.isEmpty) {
                  return Center(
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
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(marketplaceListingsProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final listing = filtered[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: PropertyCard(
                          listing: listing,
                          onTap: () => context.push('/property/${listing.listingId}'),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
