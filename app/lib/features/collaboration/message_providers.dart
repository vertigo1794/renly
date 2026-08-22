// app/lib/features/collaboration/message_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import '../listing/listing_providers.dart';
import 'message_repository.dart';
import 'models/message.dart';

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(Supabase.instance.client, ref.watch(listingRepositoryProvider));
});

/// Same session-state read as the copies in listing_providers.dart,
/// requirement_providers.dart, matching_providers.dart, and
/// cobroke_request_providers.dart -- duplicated here rather than imported
/// from a sibling feature, same established reasoning as those files.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

/// Live-updating message list for one request. StreamProvider.family is
/// autoDispose by default: when ChatScreen is popped, the underlying
/// Realtime subscription is cancelled automatically, and reopening the
/// screen establishes a fresh subscription (whose first emission is the
/// full current history, per messagesStream's own contract).
final messagesStreamProvider = StreamProvider.family<List<Message>, String>((ref, requestId) {
  return ref.watch(messageRepositoryProvider).messagesStream(requestId);
});
