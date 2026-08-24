import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/notifications/recipient_resolver.dart';

void main() {
  group('resolveMatchRecipients', () {
    test('maps each inserted row to its owner via the given key', () {
      final recipients = resolveMatchRecipients(
        insertedRows: [
          {'listing_id': 'L1', 'requirement_id': 'R1', 'score': 80},
          {'listing_id': 'L2', 'requirement_id': 'R2', 'score': 90},
        ],
        ownerKey: 'requirement_id',
        ownerNegotiatorIdByKey: {'R1': 'N1', 'R2': 'N2'},
      );
      expect(recipients, ['N1', 'N2']);
    });

    test('empty inserted rows yields no recipients', () {
      final recipients = resolveMatchRecipients(
        insertedRows: const [],
        ownerKey: 'requirement_id',
        ownerNegotiatorIdByKey: const {'R1': 'N1'},
      );
      expect(recipients, isEmpty);
    });

    test('a row whose key is missing from the owner map is skipped, not crashed on', () {
      final recipients = resolveMatchRecipients(
        insertedRows: [
          {'listing_id': 'L1', 'requirement_id': 'R_UNKNOWN', 'score': 80},
        ],
        ownerKey: 'requirement_id',
        ownerNegotiatorIdByKey: {'R1': 'N1'},
      );
      expect(recipients, isEmpty);
    });
  });

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
