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
