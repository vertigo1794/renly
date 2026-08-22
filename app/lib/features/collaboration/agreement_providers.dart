// app/lib/features/collaboration/agreement_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import 'agreement_repository.dart';
import 'models/agreement.dart';

final agreementRepositoryProvider = Provider<AgreementRepository>((ref) {
  return AgreementRepository(Supabase.instance.client);
});

/// Same session-state read as the copies in listing_providers.dart,
/// requirement_providers.dart, matching_providers.dart,
/// cobroke_request_providers.dart, and message_providers.dart --
/// duplicated here rather than imported from a sibling feature, same
/// established reasoning as those files.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

/// The current agreement for one cobroke_request, if any. The
/// .autoDispose HERE IS REQUIRED, not the default -- in the Riverpod
/// version this project is pinned to (2.6.1), `.family` alone does NOT
/// default to autoDispose (that's a Riverpod 3.x behavior, confirmed the
/// hard way during Messaging's final review -- see
/// message_providers.dart's messagesStreamProvider comment). Without it,
/// a stale fetch for a previously-viewed row would never be discarded.
final agreementForRequestProvider = FutureProvider.autoDispose.family<Agreement?, String>((ref, requestId) {
  return ref.watch(agreementRepositoryProvider).fetchAgreementForRequest(requestId);
});
