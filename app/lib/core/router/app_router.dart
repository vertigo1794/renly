import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_providers.dart';
import '../../features/auth/auth_selection_screen.dart';
import '../../features/auth/home_placeholder_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/registration_personal_screen.dart';
import '../../features/auth/registration_professional_screen.dart';
import '../../features/auth/verification_pending_screen.dart';

const _publicRoutes = {'/', '/login', '/register/personal', '/register/professional'};

/// Pure redirect decision, unit-tested independently of GoRouter/Riverpod:
/// an unauthenticated session may only reach the public auth/registration
/// routes; anything else bounces back to '/'. Authenticated sessions are
/// never redirected by this function -- the pending-vs-approved routing
/// decision happens inside LoginScreen's submit handler, not here.
String? computeAuthRedirect({required bool hasSession, required String location}) {
  if (!hasSession && !_publicRoutes.contains(location)) {
    return '/';
  }
  return null;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final hasSession = authState.valueOrNull?.session != null;

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) => computeAuthRedirect(hasSession: hasSession, location: state.matchedLocation),
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthSelectionScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register/personal',
        builder: (context, state) => const RegistrationPersonalScreen(),
      ),
      GoRoute(
        path: '/register/professional',
        builder: (context, state) => RegistrationProfessionalScreen(negotiatorId: state.extra as String),
      ),
      GoRoute(
        path: '/verification-pending',
        builder: (context, state) => const VerificationPendingScreen(),
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomePlaceholderScreen()),
    ],
  );
});
