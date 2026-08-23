/// A narrower, on-demand read of the negotiator row's identity columns --
/// deliberately separate from the Profile feature's own fetchMyProfile,
/// which excludes ic_number/phone_number to avoid pulling PII into memory
/// on every Profile screen view. This model exists only for the Account
/// settings screen, fetched only when that screen is opened.
class IdentityInfo {
  final String? icNumber;
  final String? phoneNumber;
  final String? renNumber;

  const IdentityInfo({this.icNumber, this.phoneNumber, this.renNumber});

  factory IdentityInfo.fromJson(Map<String, dynamic> json) {
    return IdentityInfo(
      icNumber: json['ic_number'] as String?,
      phoneNumber: json['phone_number'] as String?,
      renNumber: json['ren_number'] as String?,
    );
  }
}
