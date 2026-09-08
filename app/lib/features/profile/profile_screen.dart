// app/lib/features/profile/profile_screen.dart
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/brutalist_card.dart';
import '../../core/widgets/negotiator_avatar.dart';
import '../../core/widgets/r_star_badge.dart';
import '../auth/auth_providers.dart';
import '../listing/listing_formatting.dart';
import '../notifications/notification_providers.dart';
import '../ratings/rating_providers.dart' hide currentNegotiatorIdProvider;
import 'models/profile.dart';
import 'profile_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'profile_status_approved'.tr();
      case 'rejected':
        return 'profile_status_rejected'.tr();
      default:
        return 'profile_status_pending'.tr();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final countsAsync = ref.watch(profileCountsProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final ownProfile = profileAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
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
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(PhosphorIcons.shareNetwork(PhosphorIconsStyle.bold)),
            onPressed: ownProfile == null
                ? null
                : () => SharePlus.instance.share(
                      ShareParams(text: 'REN ${ownProfile.renNumber ?? '-'} • ${ownProfile.fullName}'),
                    ),
          ),
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
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: profileAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
          // Pull-to-refresh restores what this screen lost when '/profile'
          // became a StatefulShellRoute.indexedStack branch: as a pushed
          // route it disposed on pop, so myProfileProvider/profileCountsProvider
          // (both autoDispose, refetch-on-entry) refetched on the next visit.
          // The shell keeps every branch mounted for the whole session, so
          // without this the listing/deal counts go stale until app restart.
          data: (profile) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myProfileProvider);
              ref.invalidate(profileCountsProvider);
            },
            child: SingleChildScrollView(
              // Required, not decoration: the profile body is often shorter
              // than the viewport, and a non-scrollable child gives
              // RefreshIndicator no drag gesture to attach to.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(profile.fullName, style: Theme.of(context).textTheme.headlineMedium, overflow: TextOverflow.ellipsis),
                      ),
                      if (profile.verificationStatus == 'approved') ...[
                        const SizedBox(width: 6),
                        Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.fill), size: 18, color: const Color(0xFF059669)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Chip(label: Text(_statusLabel(profile.verificationStatus))),
                  const SizedBox(height: 12),
                  Text('${'profile_ren_number_label'.tr()}: ${profile.renNumber ?? '-'}'),
                  const SizedBox(height: 4),
                  Text('${'profile_agency_label'.tr()}: ${profile.agencyName ?? '-'}'),
                  const SizedBox(height: 20),
                  countsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (error, stack) => const SizedBox.shrink(),
                    data: (counts) => Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _StatCard(value: '${counts.$1}', label: 'profile_active_listings_label'.tr())),
                            const SizedBox(width: 12),
                            Expanded(child: _StatCard(value: '${counts.$2}', label: 'profile_deals_closed_label'.tr())),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _TrustScoreCard(negotiatorId: profile.negotiatorId)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                value: ListingFormatting.formatPrice(counts.$3, 'sale'),
                                label: 'profile_cobroke_volume_label'.tr(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _EditForm(profile: profile),
                  const SizedBox(height: 20),
                  BrutalistCard(
                    padding: EdgeInsets.zero,
                    // BrutalistCard is a plain opaque Container -- ink splashes
                    // from a ListTile's onTap paint on the nearest Material
                    // ancestor, which without this wrapper is the Scaffold's,
                    // underneath the card's fill (invisible). This Material
                    // gives each row's ripple somewhere visible to paint.
                    child: Material(
                      color: Colors.transparent,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('settings_section_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.notifications_active),
                            title: Text('settings_notification_row_title'.tr()),
                            subtitle: Text('settings_notification_row_subtitle'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/settings/notification'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.manage_accounts),
                            title: Text('settings_account_row_title'.tr()),
                            subtitle: Text('settings_account_row_subtitle'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/settings/account'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.privacy_tip),
                            title: Text('settings_privacy_row_title'.tr()),
                            subtitle: Text('settings_privacy_row_subtitle'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/settings/privacy'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.help_outline),
                            title: Text('settings_help_row_title'.tr()),
                            subtitle: Text('settings_help_row_subtitle'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/settings/help'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.workspace_premium),
                            title: Text('settings_subscription_row_title'.tr()),
                            subtitle: Text('settings_subscription_row_subtitle'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/settings/subscription'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.assignment_outlined),
                            title: Text('profile_requirement_board_row_title'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/requirement-board'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.list_alt_outlined),
                            title: Text('profile_my_requirements_row_title'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/my-requirements'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.handshake_outlined),
                            title: Text('profile_my_matches_row_title'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/my-matches'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.inbox_outlined),
                            title: Text('profile_my_requests_row_title'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/my-requests'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('profile_language_label'.tr(), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'en', label: Text('profile_language_en'.tr())),
                      ButtonSegment(value: 'ms', label: Text('profile_language_ms'.tr())),
                    ],
                    selected: {context.locale.languageCode},
                    onSelectionChanged: (selection) => context.setLocale(Locale(selection.first)),
                  ),
                  const SizedBox(height: 32),
                  BrutalistButton(
                    label: 'profile_sign_out'.tr(),
                    variant: BrutalistButtonVariant.secondary,
                    icon: PhosphorIcons.signOut(PhosphorIconsStyle.bold),
                    onPressed: () async {
                      try {
                        await ref.read(authRepositoryProvider).signOut();
                      } catch (_) {
                        // Sign-out already clears the local session before any
                        // network call and swallows most HTTP errors -- a
                        // rethrow here would only be a transport failure after
                        // the local session is already gone, so the redirect
                        // to '/' still happens regardless. Swallow rather than
                        // show an error the user can't act on.
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return BrutalistCard(
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          Text(label),
        ],
      ),
    );
  }
}

class _TrustScoreCard extends ConsumerWidget {
  const _TrustScoreCard({required this.negotiatorId});

  final String negotiatorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratingsAsync = ref.watch(ratingsForNegotiatorProvider(negotiatorId));

    return ratingsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (candidates) {
        final display = candidates.isEmpty
            ? 'profile_no_ratings_yet'.tr()
            : (candidates.map((c) => c.rating.stars).reduce((a, b) => a + b) / candidates.length)
                .toStringAsFixed(1);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push('/reviews'),
            child: BrutalistCard(
              child: Column(
                children: [
                  Text(display, style: Theme.of(context).textTheme.headlineSmall),
                  Text('profile_trust_score_label'.tr()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  late final TextEditingController _territoryController;
  late final TextEditingController _specialisationController;
  bool _submitting = false;
  bool _uploadingAvatar = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _territoryController = TextEditingController(text: widget.profile.territory ?? '');
    _specialisationController = TextEditingController(text: widget.profile.propertySpecialisation ?? '');
  }

  // After a successful save, ref.invalidate(myProfileProvider) causes
  // ProfileScreen to rebuild with a fresh Profile instance -- but since
  // _EditForm occupies the same slot with the same widget type, Flutter
  // reuses this State and initState does NOT re-run, so the controllers
  // would otherwise never resync to the newly-fetched canonical values.
  @override
  void didUpdateWidget(covariant _EditForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.profile.territory != oldWidget.profile.territory) {
      _territoryController.text = widget.profile.territory ?? '';
    }
    if (widget.profile.propertySpecialisation != oldWidget.profile.propertySpecialisation) {
      _specialisationController.text = widget.profile.propertySpecialisation ?? '';
    }
  }

  @override
  void dispose() {
    _territoryController.dispose();
    _specialisationController.dispose();
    super.dispose();
  }

  Future<void> _uploadAvatar() async {
    final negotiatorId = ref.read(currentNegotiatorIdProvider);
    if (negotiatorId == null) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    if (mounted) setState(() => _submitError = null);
    try {
      if (mounted) setState(() => _uploadingAvatar = true);
      final Uint8List bytes = await picked.readAsBytes();
      final repository = ref.read(profileRepositoryProvider);
      final avatarUrl = await repository.uploadAvatar(negotiatorId: negotiatorId, bytes: bytes);
      await repository.updateAvatarUrl(negotiatorId: negotiatorId, avatarUrl: avatarUrl);
      ref.invalidate(myProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('profile_save_success'.tr())),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _submitError = 'listing_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _save() async {
    final negotiatorId = ref.read(currentNegotiatorIdProvider);
    if (negotiatorId == null) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            negotiatorId: negotiatorId,
            territory: _territoryController.text.trim().isEmpty ? null : _territoryController.text.trim(),
            propertySpecialisation:
                _specialisationController.text.trim().isEmpty ? null : _specialisationController.text.trim(),
          );
      ref.invalidate(myProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('profile_save_success'.tr())),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _submitError = 'listing_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: GestureDetector(
            onTap: _uploadingAvatar ? null : _uploadAvatar,
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    NegotiatorAvatar(fullName: widget.profile.fullName, avatarUrl: widget.profile.avatarUrl, size: 72),
                    if (_uploadingAvatar) const CircularProgressIndicator(),
                  ],
                ),
                const SizedBox(height: 6),
                Text('profile_avatar_upload_hint'.tr(), style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _territoryController,
          decoration: InputDecoration(labelText: 'profile_territory_label'.tr()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _specialisationController,
          decoration: InputDecoration(labelText: 'profile_specialisation_label'.tr()),
        ),
        if (_submitError != null) ...[
          const SizedBox(height: 8),
          Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 12),
        BrutalistButton(
          label: 'profile_save'.tr(),
          icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
          onPressed: _submitting ? null : _save,
        ),
      ],
    );
  }
}
