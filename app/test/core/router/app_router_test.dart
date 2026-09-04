import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/core/router/app_router.dart';

void main() {
  group('CurrentLocationObserver', () {
    // go_router's own Page.name is the raw route template (e.g.
    // '/messages/:requestId'), never the resolved location -- the observer
    // must substitute the matched path parameters (carried in
    // RouteSettings.arguments) back into the template itself.
    MaterialPageRoute<void> routeFor(String template, Map<String, String> args) {
      return MaterialPageRoute<void>(
        settings: RouteSettings(name: template, arguments: args),
        builder: (_) => const SizedBox.shrink(),
      );
    }

    test('didPush resolves a templated path with its matched parameter', () {
      final observer = CurrentLocationObserver();
      observer.didPush(routeFor('/messages/:requestId', {'requestId': '8c6c81ba'}), null);
      expect(observer.currentLocation.value, '/messages/8c6c81ba');
    });

    test('didPush with no path parameters keeps the template as-is', () {
      final observer = CurrentLocationObserver();
      observer.didPush(routeFor('/my-requests', {}), null);
      expect(observer.currentLocation.value, '/my-requests');
    });

    test('didPop restores the previous route location', () {
      final observer = CurrentLocationObserver();
      observer.didPush(routeFor('/messages/:requestId', {'requestId': 'X1'}), null);
      final previous = routeFor('/my-requests', {});
      observer.didPop(routeFor('/messages/:requestId', {'requestId': 'X1'}), previous);
      expect(observer.currentLocation.value, '/my-requests');
    });

    test('a route with no settings name is ignored, keeping the last known location', () {
      final observer = CurrentLocationObserver();
      observer.didPush(routeFor('/my-requests', {}), null);
      observer.didPush(MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()), null);
      expect(observer.currentLocation.value, '/my-requests');
    });
  });

  group('computeAuthRedirect', () {
    test('unauthenticated user on /onboarding is allowed', () {
      expect(computeAuthRedirect(hasSession: false, location: '/onboarding'), isNull);
    });

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

    test('unauthenticated user on /my-requests is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/my-requests'), '/');
    });
  });
}
