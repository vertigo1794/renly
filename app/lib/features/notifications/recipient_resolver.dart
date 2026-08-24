/// Given the rows a match upsert's .select() actually returned (only
/// genuinely-new rows -- PostgREST's RETURNING skips ignoreDuplicates
/// conflicts), maps each to its recipient via a pre-built owner lookup the
/// caller already has in scope from its own compute loop. ownerKey is
/// 'requirement_id' when computing from a freshly-posted Listing (notify
/// the requirement owners), or 'listing_id' when computing from a
/// freshly-posted Requirement (notify the listing owners).
List<String> resolveMatchRecipients({
  required List<Map<String, dynamic>> insertedRows,
  required String ownerKey,
  required Map<String, String> ownerNegotiatorIdByKey,
}) {
  final recipients = <String>[];
  for (final row in insertedRows) {
    final key = row[ownerKey] as String?;
    final ownerId = key == null ? null : ownerNegotiatorIdByKey[key];
    if (ownerId != null) recipients.add(ownerId);
  }
  return recipients;
}

/// Shared shape for co-broke-request and message recipient resolution:
/// given a match's two owning negotiators and who just acted (the request
/// initiator, or a message sender), returns whichever side is NOT the
/// actor. Returns null if the actor matches neither side, which should
/// never happen for a valid match but is handled rather than crashed on.
String? resolveOtherPartyInMatch({
  required String actorId,
  required String listingNegotiatorId,
  required String requirementNegotiatorId,
}) {
  if (actorId == listingNegotiatorId) return requirementNegotiatorId;
  if (actorId == requirementNegotiatorId) return listingNegotiatorId;
  return null;
}
