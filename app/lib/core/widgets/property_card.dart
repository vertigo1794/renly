import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../features/listing/listing_formatting.dart';
import '../../features/listing/listing_photo.dart';
import '../../features/listing/models/listing.dart';
import '../theme/app_colors.dart';
import 'brutalist_card.dart';
import 'status_badge.dart';

/// A reusable property summary card -- extracted from the inline
/// BrutalistCard+InkWell markup marketplace_screen.dart used to build
/// directly in its ListView.builder, so the Marketplace list and the
/// Dashboard's Recent Listings carousel render identically and never drift.
/// Bed/bathtub icons switched from marketplace_screen.dart's original
/// Icons.bed/Icons.bathtub to PhosphorIcons here, to match this widget's own
/// new code (and this milestone's PhosphorIcons-only constraint for
/// new/changed icons). This is NOT app-wide yet:
/// property_detail_screen.dart, requirement_detail_screen.dart and
/// requirement_board_screen.dart still render Icons.bed/Icons.bathtub --
/// converting those is a separate, not-yet-done cleanup.
class PropertyCard extends StatelessWidget {
  const PropertyCard({required this.listing, required this.onTap, this.trailing, super.key});

  final Listing listing;
  final VoidCallback onTap;

  /// Optional small trailing content shown under the title (e.g. a
  /// relative timestamp on the Dashboard's Recent Listings feed). Null by
  /// default -- every other existing caller of this widget is unaffected.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: BrutalistCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (listing.photoUrls.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: ListingPhoto(path: listing.photoUrls.first),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            listing.title,
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (listing.status == 'active')
                          StatusBadge(label: 'listing_status_available'.tr()),
                      ],
                    ),
                    if (trailing != null) ...[
                      const SizedBox(height: 2),
                      trailing!,
                    ],
                    const SizedBox(height: 4),
                    Text(
                      ListingFormatting.formatPrice(listing.price, listing.transactionType),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.ink),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (listing.bedrooms != null) ...[
                          Icon(PhosphorIcons.bed(PhosphorIconsStyle.bold), size: 16),
                          const SizedBox(width: 4),
                          Text('${listing.bedrooms}'),
                          const SizedBox(width: 12),
                        ],
                        if (listing.bathrooms != null) ...[
                          Icon(PhosphorIcons.bathtub(PhosphorIconsStyle.bold), size: 16),
                          const SizedBox(width: 4),
                          Text('${listing.bathrooms}'),
                          const SizedBox(width: 12),
                        ],
                        Flexible(
                          child: Text(
                            listing.area,
                            style: Theme.of(context).textTheme.labelSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}
