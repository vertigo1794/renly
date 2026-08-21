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

    test('unauthenticated user on /marketplace is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/marketplace'), '/');
    });

    test('unauthenticated user on /my-inventory is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/my-inventory'), '/');
    });

    test('unauthenticated user on /post-listing is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/post-listing'), '/');
    });

    test('unauthenticated user on /property/l-1 is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/property/l-1'), '/');
    });

    test('unauthenticated user on /requirement-board is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/requirement-board'), '/');
    });

    test('unauthenticated user on /my-requirements is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/my-requirements'), '/');
    });

    test('unauthenticated user on /post-requirement is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/post-requirement'), '/');
    });

    test('unauthenticated user on /requirement-board/r-1 is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/requirement-board/r-1'), '/');
    });

    test('unauthenticated user on /property/l-1/matches is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/property/l-1/matches'), '/');
    });

    test('unauthenticated user on /requirement-board/r-1/matches is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/requirement-board/r-1/matches'), '/');
    });

    test('unauthenticated user on /my-matches is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/my-matches'), '/');
    });
  });
}
