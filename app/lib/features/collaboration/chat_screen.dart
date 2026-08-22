// app/lib/features/collaboration/chat_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../listing/models/listing_owner.dart';
import 'message_providers.dart';

final _senderNameProvider = FutureProvider.family<ListingOwner, String>((ref, negotiatorId) {
  return ref.watch(messageRepositoryProvider).fetchSenderName(negotiatorId);
});

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.requestId});

  final String requestId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send(String senderId) async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(messageRepositoryProvider).sendMessage(
            requestId: widget.requestId,
            senderId: senderId,
            body: body,
          );
      _controller.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('listing_error_generic'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentNegotiatorId = ref.watch(currentNegotiatorIdProvider);
    final messagesAsync = ref.watch(messagesStreamProvider(widget.requestId));

    return Scaffold(
      appBar: AppBar(title: Text('message_chat_title'.tr())),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(child: Text('message_empty'.tr()));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isOwn = message.senderId == currentNegotiatorId;
                    return Align(
                      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            if (!isOwn) _SenderLabel(negotiatorId: message.senderId),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isOwn
                                    ? Theme.of(context).colorScheme.primaryContainer
                                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(message.body),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (currentNegotiatorId != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(hintText: 'message_input_hint'.tr()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _sending ? null : () => _send(currentNegotiatorId),
                    child: Text('message_send'.tr()),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SenderLabel extends ConsumerWidget {
  const _SenderLabel({required this.negotiatorId});

  final String negotiatorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownerAsync = ref.watch(_senderNameProvider(negotiatorId));
    return ownerAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (owner) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(owner.fullName, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}
