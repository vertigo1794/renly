/// The current negotiator's own full profile -- composed from `negotiator`
/// plus a follow-up `agency` lookup for the firm name. Deliberately
/// separate from the auth feature's own scoped-down `Negotiator` model
/// (which only carries the 3 fields the router redirect needs).
class Profile {
  final String negotiatorId;
  final String fullName;
  final String? renNumber;
  final String? agencyName;
  final String? territory;
  final String? propertySpecialisation;
  final String verificationStatus;

  const Profile({
    required this.negotiatorId,
    required this.fullName,
    this.renNumber,
    this.agencyName,
    this.territory,
    this.propertySpecialisation,
    required this.verificationStatus,
  });

  /// [agencyName] is passed separately because it comes from a second
  /// composed query (the `agency` table), not a column on `negotiator`
  /// itself -- there is no `agency_name` key in [json].
  factory Profile.fromJson(Map<String, dynamic> json, {String? agencyName}) {
    return Profile(
      negotiatorId: json['negotiator_id'] as String,
      fullName: json['full_name'] as String,
      renNumber: json['ren_number'] as String?,
      agencyName: agencyName,
      territory: json['territory'] as String?,
      propertySpecialisation: json['property_specialisation'] as String?,
      verificationStatus: json['verification_status'] as String,
    );
  }
}
