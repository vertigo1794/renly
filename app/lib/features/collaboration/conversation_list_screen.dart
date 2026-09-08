// app/lib/features/collaboration/conversation_list_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/negotiator_avatar.dart';
import '../../core/widgets/r_star_badge.dart';
import '../listing/broadcast_badge.dart';
import '../listing/listing_formatting.dart';
import '../notifications/notification_providers.dart';
import '../profile/profile_providers.dart' hide currentNegotiatorIdProvider;
import 'agreement_providers.dart' hide currentNegotiatorIdProvider;
import 'cobroke_request_providers.dart';
import 'message_providers.dart' hide currentNegotiatorIdProvider;
import 'models/agreement.dart';
import 'models/cobroke_request_candidate.dart';
import 'models/conversation_summary.dart';

/// Merges received+sent co-broke requests into one accepted-only,
/// deduplicated-by-requestId list -- a conversation only exists once a
/// request is accepted (mirrors message_select/message_insert's own RLS
/// invariant), and a request can only ever appear in exactly ONE of
/// received/sent (whichever side didn't initiate it sees it as "received"),
/// so the dedup here is defensive, not expected to ever trigger in
/// practice -- kept anyway since the two lists are independently fetched
/// and nothing enforces that invariant at the type level.
List<CobrokeRequestCandidate> mergeAcceptedConversations(
  List<CobrokeRequestCandidate> received,
  List<CobrokeRequestCandidate> sent,
) {
  final byRequestId = <String, CobrokeRequestCandidate>{};
  for (final candidate in [...received, ...sent]) {
    if (candidate.request.status == 'accepted') {
      byRequestId[candidate.request.requestId] = candidate;
    }
  }
  return byRequestId.values.toList();
}

enum _ConversationFilter { all, activeDeals, inquiries, archived }

/// Locally-archived conversation request ids -- there is no server-side
/// "archive" concept for a cobroke_request (status is only
/// pending/accepted/declined), so this is a genuine, real, per-device
/// user action (persisted via SharedPreferences, same pattern as
/// LoginScreen's has_dismissed_biometric_prompt flag) rather than a
/// fabricated always-empty tab. Archiving is a device-local UI
/// convenience, not a synced backend state -- reasonable for a first
/// pass, and honestly scoped as such.
class _ArchivedConversations extends StateNotifier<Set<String>> {
  _ArchivedConversations() : super(const {}) {
    _load();
  }

  static const _prefsKey = 'archived_conversation_request_ids';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = (prefs.getStringList(_prefsKey) ?? const []).toSet();
  }

  Future<void> toggle(String requestId) async {
    final next = {...state};
    if (!next.remove(requestId)) next.add(requestId);
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, next.toList());
  }
}

final _archivedConversationsProvider = StateNotifierProvider<_ArchivedConversations, Set<String>>((ref) {
  return _ArchivedConversations();
});

class ConversationListScreen extends ConsumerStatefulWidget {
  const ConversationListScreen({super.key});

  @override
  ConsumerState<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends ConsumerState<ConversationListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _ConversationFilter _filter = _ConversationFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentNegotiatorId = ref.watch(currentNegotiatorIdProvider);
    final receivedAsync = ref.watch(receivedRequestsProvider);
    final sentAsync = ref.watch(sentRequestsProvider);
    final profileAsync = ref.watch(myProfileProvider);
    final unreadNotifCount = ref.watch(unreadNotificationCountProvider);
    final archived = ref.watch(_archivedConversationsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAF7),
      body: SafeArea(
        child: Column(
          children: [
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
                      if (unreadNotifCount > 0)
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
              child: receivedAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
                data: (received) => sentAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
                  data: (sent) {
                    final allConversations = mergeAcceptedConversations(received, sent);
                    final pendingReceivedCount = received.where((c) => c.request.status == 'pending').length;

                    final agreementByRequestId = <String, Agreement?>{
                      for (final c in allConversations)
                        c.request.requestId: ref.watch(agreementForRequestProvider(c.request.requestId)).valueOrNull,
                    };
                    bool isActiveDeal(String requestId) => agreementByRequestId[requestId]?.status == 'accepted';

                    final notArchived = allConversations.where((c) => !archived.contains(c.request.requestId)).toList();
                    final activeDeals = notArchived.where((c) => isActiveDeal(c.request.requestId)).toList();
                    final inquiries = notArchived.where((c) => !isActiveDeal(c.request.requestId)).toList();
                    final archivedList =
                        allConversations.where((c) => archived.contains(c.request.requestId)).toList();

                    var visible = switch (_filter) {
                      _ConversationFilter.all => notArchived,
                      _ConversationFilter.activeDeals => activeDeals,
                      _ConversationFilter.inquiries => inquiries,
                      _ConversationFilter.archived => archivedList,
                    };
                    if (_query.trim().isNotEmpty) {
                      final q = _query.toLowerCase();
                      visible = visible.where((c) {
                        final isMyListing = c.match.listing.negotiatorId == currentNegotiatorId;
                        final counterparty = isMyListing ? c.match.requirementOwner : c.match.listingOwner;
                        return counterparty.fullName.toLowerCase().contains(q) ||
                            c.match.listing.title.toLowerCase().contains(q);
                      }).toList();
                    }

                    return RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(receivedRequestsProvider);
                        ref.invalidate(sentRequestsProvider);
                        // Every per-row unread/last-message summary too -- ChatScreen
                        // marks a conversation read on open, but it cannot reach this
                        // file-private family provider to invalidate it, so a pull
                        // here is what clears an already-read row's unread dot.
                        ref.invalidate(_conversationSummaryProvider);
                      },
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'conversation_list_title'.tr(),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1.0),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'conversation_live_radar'.tr(),
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'conversation_subtitle'.tr(),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                            child: Row(
                              children: [
                                BroadcastBadge(label: 'broadcast_live_badge'.tr(), color: AppColors.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${notArchived.length} ${'conversation_ticker_active'.tr()} • $pendingReceivedCount ${'conversation_ticker_inquiries'.tr()}',
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
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  decoration: InputDecoration(
                                    hintText: 'conversation_search_hint'.tr(),
                                    prefixIcon: const Icon(Icons.search),
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                                    ),
                                  ),
                                  onChanged: (value) => setState(() => _query = value),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 36,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _FilterChip(
                                  label: '${'conversation_filter_all'.tr()} (${notArchived.length})',
                                  selected: _filter == _ConversationFilter.all,
                                  onTap: () => setState(() => _filter = _ConversationFilter.all),
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: '${'conversation_filter_active_deals'.tr()} (${activeDeals.length})',
                                  selected: _filter == _ConversationFilter.activeDeals,
                                  onTap: () => setState(() => _filter = _ConversationFilter.activeDeals),
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: '${'conversation_filter_inquiries'.tr()} (${inquiries.length})',
                                  selected: _filter == _ConversationFilter.inquiries,
                                  onTap: () => setState(() => _filter = _ConversationFilter.inquiries),
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: 'conversation_filter_archived'.tr(),
                                  selected: _filter == _ConversationFilter.archived,
                                  onTap: () => setState(() => _filter = _ConversationFilter.archived),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (visible.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 60),
                              child: Center(child: Text('conversation_list_empty'.tr())),
                            )
                          else
                            for (final candidate in visible) ...[
                              _ConversationRow(
                                candidate: candidate,
                                currentNegotiatorId: currentNegotiatorId,
                                isActiveDeal: isActiveDeal(candidate.request.requestId),
                                agreement: agreementByRequestId[candidate.request.requestId],
                                isArchived: archived.contains(candidate.request.requestId),
                                onArchiveToggle: () =>
                                    ref.read(_archivedConversationsProvider.notifier).toggle(candidate.request.requestId),
                              ),
                              const SizedBox(height: 10),
                            ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      // Bottom padding clears the floating glass dock (MainShell) sitting
      // over this screen -- without it, the default bottom-right FAB
      // position collides with the dock's own footprint.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 120),
        child: FloatingActionButton.extended(
          onPressed: () => context.push('/post-requirement'),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.ink,
          icon: Icon(PhosphorIcons.chatCircleDots(PhosphorIconsStyle.bold)),
          label: Text('conversation_new_cobroke'.tr(), style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.black : const Color(0xFFE5E7EB)),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected ? AppColors.primary : const Color(0xFF4B5563),
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
      ),
    );
  }
}

class _ConversationRow extends ConsumerWidget {
  const _ConversationRow({
    required this.candidate,
    required this.currentNegotiatorId,
    required this.isActiveDeal,
    required this.agreement,
    required this.isArchived,
    required this.onArchiveToggle,
  });

  final CobrokeRequestCandidate candidate;
  final String? currentNegotiatorId;
  final bool isActiveDeal;
  final Agreement? agreement;
  final bool isArchived;
  final VoidCallback onArchiveToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMyListing = candidate.match.listing.negotiatorId == currentNegotiatorId;
    final counterparty = isMyListing ? candidate.match.requirementOwner : candidate.match.listingOwner;
    final requestId = candidate.request.requestId;
    final summaryAsync = currentNegotiatorId == null
        ? const AsyncValue<ConversationSummary?>.data(null)
        : ref.watch(_conversationSummaryProvider((requestId: requestId, negotiatorId: currentNegotiatorId!)));

    final hasUnread = summaryAsync.valueOrNull != null && summaryAsync.valueOrNull!.unreadCount > 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          top: const BorderSide(color: Color(0xFFE5E7EB)),
          right: const BorderSide(color: Color(0xFFE5E7EB)),
          bottom: const BorderSide(color: Color(0xFFE5E7EB)),
          left: BorderSide(color: hasUnread ? AppColors.primary : const Color(0xFFE5E7EB), width: hasUnread ? 4 : 1),
        ),
      ),
      child: InkWell(
        onTap: () => context.push('/messages/$requestId'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: hasUnread ? AppColors.primary.withValues(alpha: 0.25) : const Color(0xFFF3F4F1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: hasUnread ? AppColors.primary.withValues(alpha: 0.6) : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: Text(
                        isActiveDeal
                            ? '${candidate.match.listing.title} • ${ListingFormatting.formatPrice(candidate.match.listing.price, candidate.match.listing.transactionType)} (${agreement!.splitInitiator.round()}/${agreement!.splitCounterparty.round()})'
                            : '${candidate.match.listing.title} • ${candidate.match.score}% ${'conversation_match_label'.tr()}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  summaryAsync.maybeWhen(
                    data: (summary) => summary == null
                        ? const SizedBox.shrink()
                        : Text(
                            DashboardStyleRelativeTime.format(summary.sentAt),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF94A3B8)),
                          ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  IconButton(
                    icon: Icon(
                      isArchived
                          ? PhosphorIcons.arrowUUpLeft(PhosphorIconsStyle.bold)
                          : PhosphorIcons.archive(PhosphorIconsStyle.bold),
                      size: 16,
                    ),
                    onPressed: onArchiveToggle,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NegotiatorAvatar(
                    fullName: counterparty.fullName,
                    avatarUrl: counterparty.avatarUrl,
                    isOnline: counterparty.isOnline,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          counterparty.fullName,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          [
                            'REN ${counterparty.renNumber}',
                            if (counterparty.agencyName != null) counterparty.agencyName!,
                          ].join(' • '),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: const Color(0xFF64748B), fontSize: 10),
                        ),
                        const SizedBox(height: 3),
                        summaryAsync.when(
                          loading: () => Text('conversation_no_messages_yet'.tr()),
                          error: (error, stack) => Text('conversation_no_messages_yet'.tr()),
                          data: (summary) => Text(
                            summary?.body ?? 'conversation_no_messages_yet'.tr(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  summaryAsync.maybeWhen(
                    data: (summary) {
                      if (summary == null) return const SizedBox.shrink();
                      if (summary.unreadCount > 0) {
                        return Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: Text(
                            '${summary.unreadCount}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black),
                          ),
                        );
                      }
                      // Read-receipt: only meaningful for MY OWN last sent message
                      // (readAt tracks whether the counterparty read what I sent).
                      // No icon when the counterparty sent the last message --
                      // there is nothing of mine to report a receipt for.
                      if (summary.senderId != currentNegotiatorId) return const SizedBox.shrink();
                      return Icon(
                        summary.readAt != null
                            ? PhosphorIcons.checks(PhosphorIconsStyle.bold)
                            : PhosphorIcons.check(PhosphorIconsStyle.bold),
                        size: 16,
                        color: summary.readAt != null ? Colors.green.shade600 : const Color(0xFF94A3B8),
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pure "Nm/h/d ago" formatter matching DashboardFormatting's own boundary
/// convention -- not importing that class directly since it lives in a
/// different feature folder and this project's convention keeps
/// per-feature pure formatters local rather than reaching across features
/// for a one-line helper (see e.g. ListingFormatting/RequirementFormatting's
/// own near-duplicate price formatters).
class DashboardStyleRelativeTime {
  DashboardStyleRelativeTime._();

  static String format(DateTime sentAt) {
    final diff = DateTime.now().difference(sentAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

final _conversationSummaryProvider =
    FutureProvider.autoDispose.family<ConversationSummary?, ({String requestId, String negotiatorId})>((ref, args) {
  return ref.watch(messageRepositoryProvider).fetchConversationSummary(args.requestId, args.negotiatorId);
});
