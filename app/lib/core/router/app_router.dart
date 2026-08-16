import 'package:go_router/go_router.dart';

import '../../features/verification/verification_pending_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const VerificationPendingScreen(),
    ),
  ],
);
