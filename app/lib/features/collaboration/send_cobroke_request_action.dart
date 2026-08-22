// app/lib/features/collaboration/send_cobroke_request_action.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cobroke_request_providers.dart';

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
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('listing_error_generic'.tr())),
      );
    }
  }
}
