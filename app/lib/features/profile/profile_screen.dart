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
import '../settings/settings_providers.dart' hide currentNegotiatorIdProvider;
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
      // Same bg tone as conversation_list_screen.dart/marketplace_screen.dart
      // -- the header below now matches those screens' own header structure
      // exactly (a plain Row in the body, not a Scaffold AppBar), so the
      // page behind it should match too.
      backgroundColor: const Color(0xFFF9FAF7),
      body: SafeArea(
        child: Column(
          children: [
            // Plain Row in the body, not an AppBar -- mirrors
            // conversation_list_screen.dart's own header exactly (this
            // screen is a bottom-tab root like Chat/Marketplace, not a
            // pushed route like Property Detail, which is the one screen
            // that legitimately uses a real AppBar with a back button).
            // An AppBar's title slot reserves layout space differently and
            // was pushing the wordmark further right than this screen's
            // siblings render it.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
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
                  const Spacer(),
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
                ],
              ),
            ),
            Expanded(
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
                  // A single bordered/shadowed card for the profile-identity
                  // section (avatar, name, verified icon, REN/agency, the
                  // Edit Profile toggle) -- matches the reference mockup's
                  // own card treatment for this section, instead of these
                  // elements sitting loose in the page.
                  BrutalistCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ProfileAvatar(profile: profile),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(profile.fullName, style: Theme.of(context).textTheme.headlineMedium, overflow: TextOverflow.ellipsis, maxLines: 1),
                                  const SizedBox(height: 2),
                                  // Combined onto one line, no labels -- matches
                                  // the reference mockup's own "REN 48210 • IQI
                                  // GLOBAL" treatment, real data either way (a
                                  // missing agency just drops the "•" segment,
                                  // never a fabricated placeholder).
                                  Text(
                                    [
                                      if (profile.renNumber != null) 'REN ${profile.renNumber}',
                                      if (profile.agencyName != null) profile.agencyName!,
                                    ].join(' • '),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  // The verified checkmark now lives INSIDE
                                  // this smaller pill (not also duplicated
                                  // beside the name) -- reuses the exact
                                  // blue tint already established for
                                  // Property Detail's own "Keys on Hand"
                                  // badge, same tinted-pill convention.
                                  _VerificationBadge(status: profile.verificationStatus, label: _statusLabel(profile.verificationStatus)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _EditForm(profile: profile),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  countsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (error, stack) => const SizedBox.shrink(),
                    data: (counts) => Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                value: '${counts.$1}',
                                label: 'profile_active_listings_label'.tr(),
                                icon: PhosphorIcons.buildings(PhosphorIconsStyle.bold),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                value: '${counts.$2}',
                                label: 'profile_deals_closed_label'.tr(),
                                icon: PhosphorIcons.handshake(PhosphorIconsStyle.bold),
                              ),
                            ),
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
                                icon: PhosphorIcons.trendUp(PhosphorIconsStyle.bold),
                                highlight: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 4 separate section cards, each with its own label
                  // OUTSIDE/above it -- matches the reference mockup's own
                  // grouping instead of one combined settings card.
                  _SectionLabel('profile_cobroking_preferences_title'.tr()),
                  _CoBrokingPreferencesCard(negotiatorId: profile.negotiatorId, territory: profile.territory),
                  const SizedBox(height: 20),
                  _SectionLabel('profile_account_compliance_title'.tr()),
                  _AccountComplianceCard(profile: profile, statusLabel: _statusLabel(profile.verificationStatus)),
                  const SizedBox(height: 20),
                  _SectionLabel('profile_app_support_title'.tr()),
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
                          ListTile(
                            leading: const Icon(Icons.notifications_active),
                            title: Text('settings_notification_row_title'.tr()),
                            subtitle: Text('settings_notification_row_subtitle'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/settings/notification'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.help_outline),
                            title: Text('settings_help_row_title'.tr()),
                            subtitle: Text('settings_help_row_subtitle'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/settings/help'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.privacy_tip),
                            title: Text('settings_privacy_row_title'.tr()),
                            subtitle: Text('settings_privacy_row_subtitle'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/settings/privacy'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Real, load-bearing navigation this screen already
                  // provides that the mockup's own sections don't show --
                  // kept, just grouped under its own leftover card rather
                  // than removed just because the mockup omits them.
                  _SectionLabel('settings_section_title'.tr()),
                  BrutalistCard(
                    padding: EdgeInsets.zero,
                    child: Material(
                      color: Colors.transparent,
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.manage_accounts),
                            title: Text('settings_account_row_title'.tr()),
                            subtitle: Text('settings_account_row_subtitle'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/settings/account'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.workspace_premium),
                            title: Text('settings_subscription_row_title'.tr()),
                            subtitle: Text('settings_subscription_row_subtitle'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/settings/subscription'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.assignment_outlined),
                            title: Text('profile_requirement_board_row_title'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/requirement-board'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.list_alt_outlined),
                            title: Text('profile_my_requirements_row_title'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/my-requirements'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.handshake_outlined),
                            title: Text('profile_my_matches_row_title'.tr()),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/my-matches'),
                          ),
                          const Divider(height: 1),
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
                  // Matches the reference mockup's own Sign Out treatment --
                  // a full bordered card, red icon+text, centered -- rather
                  // than a secondary-variant BrutalistButton.
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
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
                      child: BrutalistCard(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(PhosphorIcons.signOut(PhosphorIconsStyle.bold), color: Colors.red),
                            const SizedBox(width: 8),
                            // Flexible+ellipsis, same proven-safe pattern
                            // used everywhere else this session (e.g.
                            // BrutalistButton's own label) -- "Log Out of
                            // Renly" is real content that must not overflow
                            // at narrow widths.
                            Flexible(
                              child: Text(
                                'profile_sign_out'.tr(),
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.red, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'profile_footer_tagline'.tr(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF64748B)),
                    ),
                  ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An uppercase gray label sitting OUTSIDE/above a card, matching the
/// reference mockup's own section-header treatment (e.g. "CO-BROKING
/// PREFERENCES") -- as opposed to a title row living INSIDE the card
/// itself, divided from its content.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF64748B), letterSpacing: 0.5),
      ),
    );
  }
}

/// A small tinted pill for the profile's verification status -- reuses the
/// same blue tint (`0xFFDBEAFE`/`0xFFBFDBFE`/`0xFF2563EB`) already
/// established for Property Detail's own "Keys on Hand" badge, same
/// tinted-pill convention, so this doesn't invent a new color scheme. Only
/// `approved` gets the checkmark icon -- pending/rejected show the same
/// small pill shape with a neutral tint and no icon (not asked to be
/// recolored, so left as-is beyond the size reduction).
class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({required this.status, required this.label});

  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final approved = status == 'approved';
    final background = approved ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9);
    final border = approved ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0);
    final foreground = approved ? const Color(0xFF2563EB) : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6), border: Border.all(color: border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (approved) ...[
            Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.fill), size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground, fontWeight: FontWeight.bold, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label, this.icon, this.highlight = false});

  final String value;
  final String label;
  final IconData? icon;

  /// Purely a visual/style choice (matches the mockup's own lime-highlight
  /// stat card) -- no data change based on it, defaults false so Active
  /// Listings/Deals Closed stay plain white.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = highlight ? AppColors.primary : null;
    const valueColor = AppColors.ink;
    const labelColor = Color(0xFF64748B);
    return BrutalistCard(
      color: backgroundColor,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: labelColor, letterSpacing: 0.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (icon != null) Icon(icon, size: 16, color: labelColor),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, maxLines: 1, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: valueColor)),
          ),
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
              color: AppColors.ink,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'profile_trust_score_label'.tr().toUpperCase(),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70, letterSpacing: 0.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(PhosphorIcons.star(PhosphorIconsStyle.fill), size: 16, color: AppColors.primary),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(display, maxLines: 1, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CoBrokingPreferencesCard extends ConsumerStatefulWidget {
  const _CoBrokingPreferencesCard({required this.negotiatorId, required this.territory});

  final String negotiatorId;
  final String? territory;

  @override
  ConsumerState<_CoBrokingPreferencesCard> createState() => _CoBrokingPreferencesCardState();
}

class _CoBrokingPreferencesCardState extends ConsumerState<_CoBrokingPreferencesCard> {
  // Same optimistic-override pattern as NotificationSettingsScreen._toggle
  // -- the switch's thumb moves the instant it's tapped, cleared once the
  // write+refetch settles (success or failure).
  bool? _matchOverride;

  Future<void> _toggleMatch(bool value) async {
    setState(() => _matchOverride = value);
    try {
      await ref.read(settingsRepositoryProvider).updateNotificationPreferences(
            negotiatorId: widget.negotiatorId,
            notifyMatch: value,
          );
      ref.invalidate(notificationPreferencesProvider);
      try {
        await ref.read(notificationPreferencesProvider.future);
      } catch (_) {
        // A refetch failure after a successful write shouldn't surface as
        // a write error -- the write already succeeded.
      }
      if (mounted) setState(() => _matchOverride = null);
    } catch (_) {
      if (mounted) {
        setState(() => _matchOverride = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('listing_error_generic'.tr())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);

    // No internal title -- the section label now sits OUTSIDE the card
    // (via _SectionLabel), matching the reference mockup's own treatment
    // (an uppercase gray label above a plain white bordered card, not a
    // title row divided from the card's own content).
    return BrutalistCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            prefsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (error, stack) => ListTile(
                title: Text('listing_error_generic'.tr()),
                trailing: TextButton(
                  onPressed: () => ref.invalidate(notificationPreferencesProvider),
                  child: Text('agreement_retry'.tr()),
                ),
              ),
              data: (prefs) => SwitchListTile(
                title: Text('profile_auto_match_radar_label'.tr()),
                subtitle: Text('profile_auto_match_radar_subtitle'.tr()),
                value: _matchOverride ?? prefs.notifyMatch,
                onChanged: _toggleMatch,
              ),
            ),
            if (widget.territory != null) ...[
              const Divider(height: 1),
              ListTile(
                title: Text('profile_designated_area_label'.tr()),
                subtitle: Text(widget.territory!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Embeddable content only -- no outer BrutalistCard/Material of its own,
/// Groups the real REN verification status alongside the real biometric
/// status into one card, matching the reference mockup's own "Account &
/// Compliance" section -- Bank Account & Payouts (shown in the mockup)
/// stays dropped per the approved design doc, no backing subsystem exists.
class _AccountComplianceCard extends StatelessWidget {
  const _AccountComplianceCard({required this.profile, required this.statusLabel});

  final Profile profile;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    return BrutalistCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text('profile_ren_verification_title'.tr()),
              subtitle: Text(statusLabel),
              trailing: profile.verificationStatus == 'approved'
                  ? Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.fill), color: const Color(0xFF059669))
                  : null,
            ),
            const _BiometricStatusRow(),
          ],
        ),
      ),
    );
  }
}

/// Embeddable content only -- no outer BrutalistCard/Material of its own,
/// so `_AccountComplianceCard` can place this alongside the REN
/// verification row inside ONE shared card (matching the reference
/// mockup's own "Account & Compliance" grouping) rather than this row
/// floating as its own separate card. Renders its own leading Divider so
/// the caller doesn't need to know in advance whether this row will be
/// visible (never available on most emulators/devices with no biometric
/// hardware enrolled).
class _BiometricStatusRow extends ConsumerWidget {
  const _BiometricStatusRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availableAsync = ref.watch(biometricAvailableProvider);
    final enabledAsync = ref.watch(biometricLoginEnabledProvider);

    return availableAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (available) {
        if (!available) return const SizedBox.shrink();
        return enabledAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (error, stack) => const SizedBox.shrink(),
          data: (enabled) => Column(
            children: [
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.fingerprint),
                title: Text('profile_biometric_label'.tr()),
                subtitle: Text(enabled ? 'account_settings_biometric_enabled'.tr() : 'account_settings_biometric_disabled'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/account'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileAvatar extends ConsumerStatefulWidget {
  const _ProfileAvatar({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends ConsumerState<_ProfileAvatar> {
  bool _uploading = false;
  String? _error;

  Future<void> _upload() async {
    final negotiatorId = ref.read(currentNegotiatorIdProvider);
    if (negotiatorId == null) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    if (mounted) setState(() => _error = null);
    try {
      if (mounted) setState(() => _uploading = true);
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
      if (mounted) setState(() => _error = 'listing_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // No outer Center -- this now sits beside the name/REN column inside
    // the profile-identity BrutalistCard (matching the reference mockup's
    // own avatar-top-left layout), not standalone across the full page
    // width. No upload-hint caption (matches the mockup, which has none --
    // the avatar itself stays real/tappable, only the decorative caption
    // text is dropped) -- SizedBox still caps width so a shown error
    // message wraps instead of forcing the Row wider than the avatar.
    return SizedBox(
      width: 72,
      child: GestureDetector(
        onTap: _uploading ? null : _upload,
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                NegotiatorAvatar(fullName: widget.profile.fullName, avatarUrl: widget.profile.avatarUrl, size: 72, square: true),
                if (_uploading) const CircularProgressIndicator(),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
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
  bool _editing = false;
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

  Future<void> _save() async {
    final negotiatorId = ref.read(currentNegotiatorIdProvider);
    if (negotiatorId == null) {
      setState(() => _submitError = 'listing_error_generic'.tr());
      return;
    }
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

  Future<void> _saveAndClose() async {
    await _save();
    if (mounted && _submitError == null) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BrutalistButton(
          label: 'profile_edit_button'.tr(),
          icon: PhosphorIcons.pencilSimple(PhosphorIconsStyle.bold),
          variant: BrutalistButtonVariant.dark,
          onPressed: () => setState(() => _editing = !_editing),
        ),
        if (_editing) ...[
          const SizedBox(height: 12),
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
            onPressed: _submitting ? null : _saveAndClose,
          ),
        ],
      ],
    );
  }
}
