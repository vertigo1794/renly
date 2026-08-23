// app/test/features/profile/models/profile_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/profile/models/profile.dart';

void main() {
  group('Profile.fromJson', () {
    test('parses negotiator columns with no agency name provided', () {
      final profile = Profile.fromJson({
        'negotiator_id': 'n-1',
        'full_name': 'Aiman Yusof',
        'ren_number': '12345',
        'territory': 'Petaling Jaya',
        'property_specialisation': 'Residential',
        'verification_status': 'approved',
      });

      expect(profile.negotiatorId, 'n-1');
      expect(profile.fullName, 'Aiman Yusof');
      expect(profile.renNumber, '12345');
      expect(profile.agencyName, isNull);
      expect(profile.territory, 'Petaling Jaya');
      expect(profile.propertySpecialisation, 'Residential');
      expect(profile.verificationStatus, 'approved');
    });

    test('takes agencyName as a separate named parameter, not from json', () {
      final profile = Profile.fromJson(
        {
          'negotiator_id': 'n-2',
          'full_name': 'Siti Noraini',
          'ren_number': null,
          'territory': null,
          'property_specialisation': null,
          'verification_status': 'pending',
        },
        agencyName: 'Prestige Property Group',
      );

      expect(profile.agencyName, 'Prestige Property Group');
      expect(profile.renNumber, isNull);
      expect(profile.territory, isNull);
      expect(profile.propertySpecialisation, isNull);
    });
  });
}
