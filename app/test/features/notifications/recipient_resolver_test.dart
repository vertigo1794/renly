import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/notifications/recipient_resolver.dart';

void main() {
  group('resolveOtherPartyInMatch', () {
    test('returns the listing side when the actor is the requirement owner', () {
      final other = resolveOtherPartyInMatch(
        actorId: 'N_REQ',
        listingNegotiatorId: 'N_LISTING',
        requirementNegotiatorId: 'N_REQ',
      );
      expect(other, 'N_LISTING');
    });

    test('returns the requirement side when the actor is the listing owner', () {
      final other = resolveOtherPartyInMatch(
        actorId: 'N_LISTING',
        listingNegotiatorId: 'N_LISTING',
        requirementNegotiatorId: 'N_REQ',
      );
      expect(other, 'N_REQ');
    });

    test('returns null when the actor matches neither side', () {
      final other = resolveOtherPartyInMatch(
        actorId: 'N_STRANGER',
        listingNegotiatorId: 'N_LISTING',
        requirementNegotiatorId: 'N_REQ',
      );
      expect(other, isNull);
    });
  });
}
