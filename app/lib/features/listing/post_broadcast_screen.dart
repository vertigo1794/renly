// app/lib/features/listing/post_broadcast_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/r_star_badge.dart';
import '../notifications/notification_providers.dart';
import '../profile/profile_providers.dart' hide currentNegotiatorIdProvider;
import '../requirement/post_requirement_screen.dart';
import '../requirement/requirement_providers.dart';
import 'broadcast_badge.dart';
import 'listing_providers.dart';
import 'models/listing_draft.dart';
import 'post_listing_screen.dart';

enum PostBroadcastMode { listing, requirement }

/// Merges PostListingFormBody and PostRequirementFormBody behind a real
/// "Provide Listing / Buyer Match" toggle, per the Post Broadcast design
/// doc. Each form body keeps its OWN State object (created once, kept
/// alive by IndexedStack) -- this screen owns only the shared chrome
/// (header/ticker/toggle), never either form's fields/validation/submit
/// logic, to avoid any regression risk to the already-tested forms.
class PostBroadcastScreen extends ConsumerStatefulWidget {
  const PostBroadcastScreen({
    super.key,
    this.initialMode = PostBroadcastMode.listing,
    this.editListingId,
    this.initialDraft,
  });

  final PostBroadcastMode initialMode;
  final String? editListingId;
  final ListingDraft? initialDraft;

  @override
  ConsumerState<PostBroadcastScreen> createState() => _PostBroadcastScreenState();
}

class _PostBroadcastScreenState extends ConsumerState<PostBroadcastScreen> {
  late PostBroadcastMode _mode = widget.initialMode;

  @override
  Widget build(BuildContext context) {
    final showToggle = widget.editListingId == null;
    final isEditMode = widget.editListingId != null;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RStarBadge(size: 28),
            const SizedBox(width: 8),
            Text(
              isEditMode ? 'listing_edit_title'.tr() : 'app_name'.tr(),
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: AppColors.ink,
                    fontSize: 20,
                    letterSpacing: -1.0,
                    height: 1,
                  ),
            ),
          ],
        ),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final profileAsync = ref.watch(myProfileProvider);
              return profileAsync.maybeWhen(
                data: (profile) => profile.renNumber == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Container(
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
                              Text('REN ${profile.renNumber}', style: Theme.of(context).textTheme.labelSmall),
                            ],
                          ),
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              );
            },
          ),
          Consumer(
            builder: (context, ref, _) {
              final unreadCount = ref.watch(unreadNotificationCountProvider);
              return Stack(
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
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (showToggle) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _mode == PostBroadcastMode.listing ? const _ListingHeaderTitle() : const _RequirementHeaderTitle(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _mode == PostBroadcastMode.listing ? const _ActiveListingsTicker() : const _BuyerDemandsTicker(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _ModeToggle(mode: _mode, onChanged: (mode) => setState(() => _mode = mode)),
            ),
          ],
          Expanded(
            child: IndexedStack(
              index: _mode == PostBroadcastMode.listing ? 0 : 1,
              children: [
                PostListingFormBody(editListingId: widget.editListingId, initialDraft: widget.initialDraft),
                const PostRequirementFormBody(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final PostBroadcastMode mode;
  final ValueChanged<PostBroadcastMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEBECE7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(child: _ToggleButton(
            label: 'broadcast_provide_listing_tab'.tr(),
            icon: PhosphorIcons.building(PhosphorIconsStyle.bold),
            selected: mode == PostBroadcastMode.listing,
            onTap: () => onChanged(PostBroadcastMode.listing),
          )),
          Expanded(child: _ToggleButton(
            label: 'broadcast_buyer_match_tab'.tr(),
            icon: PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.bold),
            selected: mode == PostBroadcastMode.requirement,
            onTap: () => onChanged(PostBroadcastMode.requirement),
          )),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: selected ? AppColors.primary : const Color(0xFF4B5563)),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? AppColors.primary : const Color(0xFF4B5563),
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListingHeaderTitle extends StatelessWidget {
  const _ListingHeaderTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'broadcast_listing_headline'.tr(),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6)),
              child: Text(
                'broadcast_instant_badge'.tr(),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'broadcast_listing_subtitle'.tr(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
        ),
      ],
    );
  }
}

class _RequirementHeaderTitle extends StatelessWidget {
  const _RequirementHeaderTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'broadcast_requirement_headline'.tr(),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6)),
              child: Text(
                'broadcast_radar_badge'.tr(),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'broadcast_requirement_subtitle'.tr(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
        ),
      ],
    );
  }
}

class _ActiveListingsTicker extends ConsumerWidget {
  const _ActiveListingsTicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingsAsync = ref.watch(marketplaceListingsProvider);
    final count = listingsAsync.valueOrNull?.length ?? 0;
    return _TickerBar(text: 'broadcast_active_listings_ticker'.tr(namedArgs: {'count': '$count'}));
  }
}

class _BuyerDemandsTicker extends ConsumerWidget {
  const _BuyerDemandsTicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(openRequirementsCountProvider);
    final count = countAsync.valueOrNull ?? 0;
    return _TickerBar(text: 'broadcast_buyer_demands_ticker'.tr(namedArgs: {'count': '$count'}));
  }
}

class _TickerBar extends StatelessWidget {
  const _TickerBar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          BroadcastBadge(label: 'broadcast_live_badge'.tr(), color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 6),
          Icon(PhosphorIcons.lightning(PhosphorIconsStyle.fill), size: 14, color: AppColors.primary),
        ],
      ),
    );
  }
}
