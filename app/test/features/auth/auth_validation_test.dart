import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/auth/auth_validation.dart';

void main() {
  group('AuthValidation.isValidEmail', () {
    test('accepts a normal email', () {
      expect(AuthValidation.isValidEmail('agent@renly.my'), isTrue);
    });
    test('rejects missing @', () {
      expect(AuthValidation.isValidEmail('agent.renly.my'), isFalse);
    });
    test('rejects missing domain dot', () {
      expect(AuthValidation.isValidEmail('agent@renly'), isFalse);
    });
  });

  group('AuthValidation.isValidPassword', () {
    test('accepts 8+ characters', () {
      expect(AuthValidation.isValidPassword('password1'), isTrue);
    });
    test('rejects under 8 characters', () {
      expect(AuthValidation.isValidPassword('short1'), isFalse);
    });
  });

  group('AuthValidation.passwordsMatch', () {
    test('true when identical and non-empty', () {
      expect(AuthValidation.passwordsMatch('password1', 'password1'), isTrue);
    });
    test('false when different', () {
      expect(AuthValidation.passwordsMatch('password1', 'password2'), isFalse);
    });
    test('false when both empty', () {
      expect(AuthValidation.passwordsMatch('', ''), isFalse);
    });
  });

  group('AuthValidation.isValidIcNumber', () {
    test('accepts NNNNNN-NN-NNNN format', () {
      expect(AuthValidation.isValidIcNumber('900101-14-5555'), isTrue);
    });
    test('rejects missing dashes', () {
      expect(AuthValidation.isValidIcNumber('900101145555'), isFalse);
    });
    test('rejects wrong segment lengths', () {
      expect(AuthValidation.isValidIcNumber('900101-1-5555'), isFalse);
    });
  });

  group('AuthValidation.isValidPhoneNumber', () {
    test('accepts 012-3456789 format', () {
      expect(AuthValidation.isValidPhoneNumber('012-3456789'), isTrue);
    });
    test('accepts 3-digit prefix', () {
      expect(AuthValidation.isValidPhoneNumber('016-3456789'), isTrue);
    });
    test('rejects missing dash', () {
      expect(AuthValidation.isValidPhoneNumber('0123456789'), isFalse);
    });
  });
}
