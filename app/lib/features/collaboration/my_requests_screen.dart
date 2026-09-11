// app/lib/features/collaboration/my_requests_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/negotiator_avatar.dart';
import '../../core/widgets/r_star_badge.dart';
import '../listing/listing_formatting.dart';
import '../notifications/notification_providers.dart';
import '../profile/profile_providers.dart' hide currentNegotiatorIdProvider;
import '../requirement/requirement_formatting.dart';
import 'agreement_providers.dart' hide currentNegotiatorIdProvider;
import 'cobroke_request_providers.dart';
import 'models/cobroke_request_candidate.dart';
import 'propose_agreement_dialog.dart';
import '../ratings/rate_dialog.dart';
import '../ratings/rating_providers.dart' hide currentNegotiatorIdProvider;

/// Restyled from Stitch's "My Requests (Co-Broking Deal Pipeline)"
/// mockup: a branded header matching Requirement Board/My Requirements'
/// own (back button -- this is a pushed route outside the bottom-nav
/// shell), a real pending-review ticker, and premium cards -- the inner
/// Accept/Decline/Chat/_AgreementSection/_RatingSection content is left
/// completely untouched (same widgets, same order, same exact copy),
/// since that machinery is exhaustively covered by
/// my_requests_screen_test.dart's many exact-text assertions; only the
/// header chrome and the card's own container/decoration changed.
class MyRequestsScreen extends ConsumerStatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  ConsumerState<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends ConsumerState<MyRequestsScreen> {
  String _selectedTab = 'received';

  @override
  Widget build(BuildContext context) {
    final currentNegotiatorId = ref.watch(currentNegotiatorIdProvider);
    final profileAsync = ref.watch(myProfileProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final receivedAsync = ref.watch(receivedRequestsProvider);
    final sentAsync = ref.watch(sentRequestsProvider);

    final receivedCount = receivedAsync.valueOrNull?.length ?? 0;
    final sentCount = sentAsync.valueOrNull?.length ?? 0;
    final pendingReview = receivedAsync.valueOrNull?.where((c) => c.request.status == 'pending').length ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAF7),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(PhosphorIcons.arrowLeft(PhosphorIconsStyle.bold)),
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/home');
                      }
                    },
                  ),
                  const SizedBox(width: 4),
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
                  profileAsync.maybeWhen(
                    data: (profile) => profile.renNumber == null
                        ? const SizedBox.shrink()
                        : Container(
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
                                Text(
                                  'REN ${profile.renNumber}',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 8),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'cobroke_request_my_requests_title'.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1.0),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          '${receivedCount + sentCount} ${'cobroke_request_units_label'.tr()}',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'cobroke_request_subtitle'.tr(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),
                  if (pendingReview > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                            child: Text(
                              'broadcast_live_badge'.tr(),
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$pendingReview ${'cobroke_request_ticker_label'.tr()}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(PhosphorIcons.lightning(PhosphorIconsStyle.fill), size: 14, color: AppColors.primary),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _TabPill(
                          label: 'cobroke_request_tab_received'.tr(),
                          selected: _selectedTab == 'received',
                          onTap: () => setState(() => _selectedTab = 'received'),
                        ),
                        const SizedBox(width: 8),
                        _TabPill(
                          label: 'cobroke_request_tab_sent'.tr(),
                          selected: _selectedTab == 'sent',
                          onTap: () => setState(() => _selectedTab = 'sent'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _selectedTab == 'received'
                  ? _RequestList(
                      provider: receivedRequestsProvider,
                      isReceived: true,
                      currentNegotiatorId: currentNegotiatorId,
                    )
                  : _RequestList(
                      provider: sentRequestsProvider,
                      isReceived: false,
                      currentNegotiatorId: currentNegotiatorId,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.black : const Color(0xFFE2E5DC)),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected ? AppColors.primary : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
      ),
    );
  }
}

class _RequestList extends ConsumerWidget {
  const _RequestList({required this.provider, required this.isReceived, required this.currentNegotiatorId});

  final AutoDisposeFutureProvider<List<CobrokeRequestCandidate>> provider;
  final bool isReceived;
  final String? currentNegotiatorId;

  String _statusLabel(String status) {
    switch (status) {
      case 'accepted':
        return 'cobroke_request_status_accepted'.tr();
      case 'declined':
        return 'cobroke_request_status_declined'.tr();
      default:
        return 'cobroke_request_status_pending'.tr();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(provider);

    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
      data: (requests) {
        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: const Color(0xFFF3F4F1), shape: BoxShape.circle),
                  child: Icon(PhosphorIcons.handshake(PhosphorIconsStyle.bold), size: 32, color: const Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 16),
                Text('cobroke_request_empty'.tr()),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(provider),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final candidate = requests[index];
              final isMyListing = candidate.match.listing.negotiatorId == currentNegotiatorId;
              final counterpartyOwner = isMyListing ? candidate.match.requirementOwner : candidate.match.listingOwner;
              final counterpartyNegotiatorId =
                  isMyListing ? candidate.match.requirement.negotiatorId : candidate.match.listing.negotiatorId;
              final status = candidate.request.status;
              final statusColor = switch (status) {
                'accepted' => const Color(0xFF16A34A),
                'declined' => const Color(0xFFDC2626),
                _ => const Color(0xFFCA8A04),
              };

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E5DC)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NegotiatorAvatar(
                              fullName: counterpartyOwner.fullName,
                              avatarUrl: counterpartyOwner.avatarUrl,
                              isOnline: counterpartyOwner.isOnline,
                              size: 32,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${counterpartyOwner.fullName} (REN: ${counterpartyOwner.renNumber})',
                                style: Theme.of(context).textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration:
                                  BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                _statusLabel(status),
                                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(PhosphorIcons.mapPin(PhosphorIconsStyle.bold), size: 13, color: const Color(0xFF94A3B8)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                isMyListing
                                    ? RequirementFormatting.formatBudgetRange(
                                        candidate.match.requirement.budgetMin,
                                        candidate.match.requirement.budgetMax,
                                        candidate.match.requirement.transactionType,
                                      )
                                    : ListingFormatting.formatPrice(
                                        candidate.match.listing.price, candidate.match.listing.transactionType),
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF64748B)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFF3F4F1), borderRadius: BorderRadius.circular(6)),
                              child: Text('${candidate.match.score}/100',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      if (isReceived && candidate.request.status == 'pending') ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            BrutalistButton(
                              label: 'cobroke_request_accept'.tr(),
                              fullWidth: false,
                              icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(cobrokeRequestRepositoryProvider)
                                      .acceptRequest(candidate.request.requestId);
                                  ref.invalidate(receivedRequestsProvider);
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('listing_error_generic'.tr())),
                                    );
                                  }
                                }
                              },
                            ),
                            BrutalistButton(
                              label: 'cobroke_request_decline'.tr(),
                              variant: BrutalistButtonVariant.secondary,
                              fullWidth: false,
                              icon: PhosphorIcons.x(PhosphorIconsStyle.bold),
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(cobrokeRequestRepositoryProvider)
                                      .declineRequest(candidate.request.requestId);
                                  ref.invalidate(receivedRequestsProvider);
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('listing_error_generic'.tr())),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                      if (candidate.request.status == 'accepted') ...[
                        const SizedBox(height: 8),
                        BrutalistButton(
                          label: 'cobroke_request_chat_button'.tr(),
                          variant: BrutalistButtonVariant.secondary,
                          icon: PhosphorIcons.chatCircle(PhosphorIconsStyle.bold),
                          onPressed: () => context.push('/messages/${candidate.request.requestId}'),
                        ),
                        _AgreementSection(
                          requestId: candidate.request.requestId,
                          currentNegotiatorId: currentNegotiatorId,
                          ratedId: counterpartyNegotiatorId,
                        ),
                      ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Formats a numeric(5,2) split percentage without lossy independent
/// rounding -- e.g. a genuinely valid stored pair like 55.5 / 44.5 (sums to
/// exactly 100) must never be displayed as 56% / 45% (reads as 101%).
String _formatSplitPercent(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  final formatted = value.toStringAsFixed(2);
  return formatted.endsWith('0') ? formatted.substring(0, formatted.length - 1) : formatted;
}

class _AgreementSection extends ConsumerWidget {
  const _AgreementSection({
    required this.requestId,
    required this.currentNegotiatorId,
    required this.ratedId,
  });

  final String requestId;
  final String? currentNegotiatorId;
  final String ratedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (currentNegotiatorId == null) return const SizedBox.shrink();
    final agreementAsync = ref.watch(agreementForRequestProvider(requestId));

    return agreementAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Expanded(child: Text('listing_error_generic'.tr())),
            TextButton(
              onPressed: () => ref.invalidate(agreementForRequestProvider(requestId)),
              child: Text('agreement_retry'.tr()),
            ),
          ],
        ),
      ),
      data: (agreement) {
        if (agreement == null || agreement.status == 'declined') {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              BrutalistButton(
                label: 'agreement_propose_button'.tr(),
                variant: BrutalistButtonVariant.secondary,
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => ProposeAgreementDialog(
                    requestId: requestId,
                    initiatorId: currentNegotiatorId!,
                  ),
                ),
              ),
            ],
          );
        }

        final splitText =
            '${_formatSplitPercent(agreement.splitInitiator)}% / ${_formatSplitPercent(agreement.splitCounterparty)}%';
        final isRecipient = agreement.initiatorId != currentNegotiatorId;

        if (agreement.status == 'pending' && isRecipient) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(splitText),
              if (agreement.terms != null && agreement.terms!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(agreement.terms!),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  BrutalistButton(
                    label: 'agreement_accept'.tr(),
                    fullWidth: false,
                    icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
                    onPressed: () async {
                      try {
                        await ref.read(agreementRepositoryProvider).acceptAgreement(agreement.agreementId);
                        ref.invalidate(agreementForRequestProvider(requestId));
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('listing_error_generic'.tr())),
                          );
                        }
                      }
                    },
                  ),
                  BrutalistButton(
                    label: 'agreement_decline'.tr(),
                    variant: BrutalistButtonVariant.secondary,
                    fullWidth: false,
                    icon: PhosphorIcons.x(PhosphorIconsStyle.bold),
                    onPressed: () async {
                      try {
                        await ref.read(agreementRepositoryProvider).declineAgreement(agreement.agreementId);
                        ref.invalidate(agreementForRequestProvider(requestId));
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('listing_error_generic'.tr())),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ],
          );
        }

        if (agreement.status == 'pending') {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(splitText),
              if (agreement.terms != null && agreement.terms!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(agreement.terms!),
              ],
              const SizedBox(height: 4),
              Text('agreement_waiting_response'.tr()),
            ],
          );
        }

        // status == 'accepted'
        final acceptedAt = agreement.acceptedAt;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(splitText),
            if (agreement.terms != null && agreement.terms!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(agreement.terms!),
            ],
            const SizedBox(height: 4),
            Text(acceptedAt == null
                ? 'agreement_accepted_on'.tr()
                : '${'agreement_accepted_on'.tr()} ${acceptedAt.day}/${acceptedAt.month}/${acceptedAt.year}'),
            const SizedBox(height: 8),
            _RatingSection(
              agreementId: agreement.agreementId,
              raterId: currentNegotiatorId!,
              ratedId: ratedId,
            ),
          ],
        );
      },
    );
  }
}

class _RatingSection extends ConsumerWidget {
  const _RatingSection({required this.agreementId, required this.raterId, required this.ratedId});

  final String agreementId;
  final String raterId;
  final String ratedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratingAsync = ref.watch(myRatingForAgreementProvider(agreementId));

    return ratingAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (rating) {
        if (rating == null) {
          return BrutalistButton(
            label: 'rating_rate_button'.tr(),
            variant: BrutalistButtonVariant.secondary,
            icon: PhosphorIcons.star(PhosphorIconsStyle.bold),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => RateDialog(agreementId: agreementId, raterId: raterId, ratedId: ratedId),
            ),
          );
        }

        final withinEditWindow = DateTime.now().difference(rating.createdAt) < const Duration(hours: 24);
        if (withinEditWindow) {
          return BrutalistButton(
            label: 'rating_edit_button'.tr(),
            variant: BrutalistButtonVariant.secondary,
            icon: PhosphorIcons.star(PhosphorIconsStyle.bold),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => RateDialog(
                agreementId: agreementId,
                raterId: raterId,
                ratedId: ratedId,
                existingRating: rating,
              ),
            ),
          );
        }

        return Text('${'rating_you_rated'.tr()}: ${rating.stars}');
      },
    );
  }
}
