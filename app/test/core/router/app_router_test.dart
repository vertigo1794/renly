import 'package:flutter_test/flutter_test.dart';
import 'package:renly/core/router/app_router.dart';

void main() {
  group('computeAuthRedirect', () {
    test('unauthenticated user on / is allowed (no redirect)', () {
      expect(computeAuthRedirect(hasSession: false, location: '/'), isNull);
    });

    test('unauthenticated user on /login is allowed', () {
      expect(computeAuthRedirect(hasSession: false, location: '/login'), isNull);
    });

    test('unauthenticated user on /register/personal is allowed', () {
      expect(computeAuthRedirect(hasSession: false, location: '/register/personal'), isNull);
    });

    test('unauthenticated user on /register/professional is allowed', () {
      expect(computeAuthRedirect(hasSession: false, location: '/register/professional'), isNull);
    });

    test('unauthenticated user on /home is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/home'), '/');
    });

    test('unauthenticated user on /verification-pending is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/verification-pending'), '/');
    });

    test('authenticated user anywhere is never redirected', () {
      expect(computeAuthRedirect(hasSession: true, location: '/'), isNull);
      expect(computeAuthRedirect(hasSession: true, location: '/home'), isNull);
      expect(computeAuthRedirect(hasSession: true, location: '/verification-pending'), isNull);
    });
  });
}
