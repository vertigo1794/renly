// app/lib/features/collaboration/my_requests_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'cobroke_request_providers.dart';
import 'models/cobroke_request_candidate.dart';

/// Both directions of cobroke_request in one screen -- Received (requests
/// where the viewer can act) and Sent (requests the viewer initiated,
/// status-only). Mirrors the segmented-tab shape already established by
/// MyInventoryScreen/MyRequirementsScreen.
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

    return Scaffold(
      appBar: AppBar(title: Text('cobroke_request_my_requests_title'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'received', label: Text('cobroke_request_tab_received'.tr())),
                ButtonSegment(value: 'sent', label: Text('cobroke_request_tab_sent'.tr())),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (selection) => setState(() => _selectedTab = selection.first),
            ),
          ),
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
          return Center(child: Text('cobroke_request_empty'.tr()));
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(provider),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final candidate = requests[index];
              final isMyListing = candidate.match.listing.negotiatorId == currentNegotiatorId;
              final counterpartyOwner = isMyListing ? candidate.match.requirementOwner : candidate.match.listingOwner;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${counterpartyOwner.fullName} (REN: ${counterpartyOwner.renNumber})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text('${candidate.match.score}/100'),
                      const SizedBox(height: 4),
                      Text(_statusLabel(candidate.request.status)),
                      if (isReceived && candidate.request.status == 'pending') ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ElevatedButton(
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
                              child: Text('cobroke_request_accept'.tr()),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
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
                              child: Text('cobroke_request_decline'.tr()),
                            ),
                          ],
                        ),
                      ],
                      if (candidate.request.status == 'accepted') ...[
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => context.push('/messages/${candidate.request.requestId}'),
                          child: Text('cobroke_request_chat_button'.tr()),
                        ),
                      ],
                    ],
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
