// app/lib/features/collaboration/conversation_list_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/brutalist_card.dart';
import 'cobroke_request_providers.dart';
import 'message_providers.dart' hide currentNegotiatorIdProvider;
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

class ConversationListScreen extends ConsumerWidget {
  const ConversationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentNegotiatorId = ref.watch(currentNegotiatorIdProvider);
    final receivedAsync = ref.watch(receivedRequestsProvider);
    final sentAsync = ref.watch(sentRequestsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('conversation_list_title'.tr())),
      body: receivedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
        data: (received) => sentAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
          data: (sent) {
            final conversations = mergeAcceptedConversations(received, sent);
            if (conversations.isEmpty) {
              return Center(child: Text('conversation_list_empty'.tr()));
            }
            // Pull-to-refresh (same convention as my_requests_screen.dart /
            // marketplace_screen.dart) is the ONLY way these two autoDispose
            // providers get refetched from this screen: as a
            // StatefulShellRoute.indexedStack branch root, this screen is
            // built once and stays mounted for the whole session, so
            // switching away to another tab and back never disposes it and
            // never triggers the refetch-on-entry these providers were
            // written for.
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
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final candidate = conversations[index];
                  final isMyListing = candidate.match.listing.negotiatorId == currentNegotiatorId;
                  final counterpartyOwner =
                      isMyListing ? candidate.match.requirementOwner : candidate.match.listingOwner;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ConversationRow(
                      requestId: candidate.request.requestId,
                      counterpartyName: counterpartyOwner.fullName,
                      currentNegotiatorId: currentNegotiatorId,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ConversationRow extends ConsumerWidget {
  const _ConversationRow({
    required this.requestId,
    required this.counterpartyName,
    required this.currentNegotiatorId,
  });

  final String requestId;
  final String counterpartyName;
  final String? currentNegotiatorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (currentNegotiatorId == null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/messages/$requestId'),
          child: BrutalistCard(
            child: Text(counterpartyName, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
      );
    }

    final summaryAsync =
        ref.watch(_conversationSummaryProvider((requestId: requestId, negotiatorId: currentNegotiatorId!)));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/messages/$requestId'),
        child: BrutalistCard(
          child: summaryAsync.when(
            loading: () => Text(counterpartyName, style: Theme.of(context).textTheme.titleMedium),
            error: (error, stack) => Text(counterpartyName, style: Theme.of(context).textTheme.titleMedium),
            data: (summary) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(counterpartyName, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        summary?.body ?? 'conversation_no_messages_yet'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (summary != null && summary.unreadCount > 0)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(left: 8, top: 4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final _conversationSummaryProvider =
    FutureProvider.autoDispose.family<ConversationSummary?, ({String requestId, String negotiatorId})>((ref, args) {
  return ref.watch(messageRepositoryProvider).fetchConversationSummary(args.requestId, args.negotiatorId);
});
