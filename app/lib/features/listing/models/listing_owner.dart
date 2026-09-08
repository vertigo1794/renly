/// The listing's negotiator, scoped to what PropertyDetailScreen displays
/// (name + REN number) -- deliberately not the full `Negotiator` model from
/// the auth feature, to keep this feature's Supabase reads self-contained
/// rather than reaching into another feature's model. `agencyName` added
/// for the Main Dashboard's Co-Broking Radar card (shows the matched
/// agent's agency as a trust signal) -- nullable because the RPC's LEFT
/// JOIN on `agency` returns null for a negotiator with no `agency_id` set.
/// `verificationStatus` added for the Property Detail Ultra-Premium
/// Restyle's real verified-checkmark -- nullable for the same reason as
/// every other optional field here (absent means unknown, never assumed
/// approved). `avatarUrl`/`isOnline` added for the Negotiator Avatar +
/// Online Presence feature -- `avatarUrl` is a full public URL (the
/// avatar-photos bucket is public), nullable meaning no photo uploaded yet;
/// `isOnline` is computed server-side by the RPC from `last_seen_at`,
/// defaults false (never assumed online).
class ListingOwner {
  final String fullName;
  final String renNumber;
  final String? agencyName;
  final String? verificationStatus;
  final String? avatarUrl;
  final bool isOnline;

  const ListingOwner({
    required this.fullName,
    required this.renNumber,
    this.agencyName,
    this.verificationStatus,
    this.avatarUrl,
    this.isOnline = false,
  });

  factory ListingOwner.fromJson(Map<String, dynamic> json) {
    return ListingOwner(
      fullName: json['full_name'] as String,
      renNumber: json['ren_number'] as String? ?? '',
      agencyName: json['agency_name'] as String?,
      verificationStatus: json['verification_status'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isOnline: json['is_online'] as bool? ?? false,
    );
  }
}
