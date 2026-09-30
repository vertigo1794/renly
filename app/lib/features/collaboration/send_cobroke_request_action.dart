// app/lib/features/collaboration/send_cobroke_request_action.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cobroke_request_providers.dart';

/// True if this match already has an open (pending/accepted) cobroke_request
/// on either side -- the DB's `cobroke_request_one_open_per_match` unique
/// index rejects a second one, and previously the three match-list screens
/// never checked this first, so a user could tap an already-requested match
/// and only find out via a generic error snackbar. Falls back to false
/// while the underlying providers are still loading/erroring, same as
/// before this check existed -- the DB constraint is still the real
/// enforcement, this is purely a UX pre-check.
bool hasOpenCobrokeRequest(WidgetRef ref, String matchId) {
  final sent = ref.watch(sentRequestsProvider).valueOrNull ?? const [];
  final received = ref.watch(receivedRequestsProvider).valueOrNull ?? const [];
  return [...sent, ...received].any(
    (c) => c.match.matchId == matchId && (c.request.status == 'pending' || c.request.status == 'accepted'),
  );
}

/// Shared "Request Co-Broke" action for the three match-list screens
/// (MatchesForListingScreen, MatchesForRequirementScreen, MyMatchesScreen)
/// -- each match row already has exactly one matchId, so this needs no
/// context about which side of the match the viewer is on.
Future<void> sendCobrokeRequest(BuildContext context, WidgetRef ref, String matchId) async {
  final negotiatorId = ref.read(currentNegotiatorIdProvider);
  if (negotiatorId == null) return;

  try {
    await ref.read(cobrokeRequestRepositoryProvider).createRequest(
          matchId: matchId,
          initiatorId: negotiatorId,
        );
    ref.invalidate(sentRequestsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('cobroke_request_sent'.tr())),
      );
    }
  } catch (e) {
    debugPrint('sendCobrokeRequest failed: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('listing_error_generic'.tr())),
      );
    }
  }
}
