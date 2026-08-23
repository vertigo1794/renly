import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/settings/models/identity_info.dart';

void main() {
  group('IdentityInfo.fromJson', () {
    test('parses all three fields when present', () {
      final info = IdentityInfo.fromJson({
        'ic_number': '900101-14-1234',
        'phone_number': '012-3456789',
        'ren_number': '12345',
      });

      expect(info.icNumber, '900101-14-1234');
      expect(info.phoneNumber, '012-3456789');
      expect(info.renNumber, '12345');
    });

    test('parses null fields as null', () {
      final info = IdentityInfo.fromJson({
        'ic_number': null,
        'phone_number': null,
        'ren_number': null,
      });

      expect(info.icNumber, isNull);
      expect(info.phoneNumber, isNull);
      expect(info.renNumber, isNull);
    });
  });
}
