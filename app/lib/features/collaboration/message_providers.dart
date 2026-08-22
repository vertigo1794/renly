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

/// Live-updating message list for one request. The .autoDispose HERE IS
/// REQUIRED, not the default: in the Riverpod version this project is
/// pinned to (2.6.1), `.family` alone does NOT default to autoDispose --
/// that's a Riverpod 3.x behavior. Without the explicit modifier, popping
/// ChatScreen would NOT cancel the underlying Realtime subscription --
/// SupabaseStreamBuilder only tears down its channel when the Dart
/// subscription is cancelled, which only happens on provider disposal --
/// leaking one open Realtime channel per distinct requestId ever opened
/// for the rest of the app's process lifetime. With .autoDispose, popping
/// ChatScreen cancels the subscription, and reopening the screen
/// establishes a fresh one (whose first emission is the full current
/// history, per messagesStream's own contract).
final messagesStreamProvider = StreamProvider.autoDispose.family<List<Message>, String>((ref, requestId) {
  return ref.watch(messageRepositoryProvider).messagesStream(requestId);
});
