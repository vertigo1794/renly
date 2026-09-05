import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/auth_selection_screen.dart';
import '../../features/auth/home_placeholder_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/onboarding_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/auth/registration_personal_screen.dart';
import '../../features/auth/registration_professional_screen.dart';
import '../../features/auth/verification_pending_screen.dart';
import '../../features/collaboration/chat_screen.dart';
import '../../features/collaboration/my_requests_screen.dart';
import '../../features/listing/marketplace_screen.dart';
import '../../features/listing/my_inventory_screen.dart';
import '../../features/listing/post_listing_screen.dart';
import '../../features/listing/property_detail_screen.dart';
import '../../features/matching/matches_for_listing_screen.dart';
import '../../features/matching/matches_for_requirement_screen.dart';
import '../../features/matching/my_matches_screen.dart';
import '../../features/notifications/notification_list_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/ratings/reviews_screen.dart';
import '../../features/requirement/my_requirements_screen.dart';
import '../../features/requirement/post_requirement_screen.dart';
import '../../features/requirement/requirement_board_screen.dart';
import '../../features/requirement/requirement_detail_screen.dart';
import '../../features/settings/account_settings_screen.dart';
import '../../features/settings/help_screen.dart';
import '../../features/settings/notification_settings_screen.dart';
import '../../features/settings/privacy_screen.dart';
import '../../features/subscription/subscription_screen.dart';

const _publicRoutes = {
  '/splash',
  '/onboarding',
  '/',
  '/login',
  '/register/personal',
  '/register/professional',
};

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

/// Bridges a Stream to a ChangeNotifier so GoRouter's `refreshListenable`
/// can re-run `redirect` on every auth-state change WITHOUT the router
/// itself being recreated.
///
/// Why this matters: if `appRouterProvider` watched the auth stream and
/// rebuilt, every auth event (signIn/signOut/tokenRefreshed) would produce
/// a BRAND NEW GoRouter with a fresh GoRouteInformationProvider defaulting
/// to `initialLocation: '/'`. Flutter's Router widget sees a different
/// routeInformationProvider and resets the whole navigation stack to '/',
/// which silently killed mid-flow navigation (e.g. signUp() firing
/// `signedIn` during registration Step 1 unmounted the screen before
/// `context.push('/register/professional')` could run).
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// GoRouter's own `routerDelegate.currentConfiguration.uri` only reflects
/// the last `go()`-navigated location -- it does NOT update for `push()`,
/// which this codebase uses for every secondary screen (including
/// ChatScreen). A NavigatorObserver sees every push/pop/replace on the
/// actual Navigator stack regardless of which method triggered it, so it's
/// the only reliable way to know what screen is really on top right now.
/// [currentLocationObserver] is the single instance shared between the
/// router (which feeds it route changes) and main.dart's foreground-message
/// handler (which reads [currentLocation] to decide whether to suppress a
/// push banner for the chat the recipient already has open).
class CurrentLocationObserver extends NavigatorObserver {
  final ValueNotifier<String?> currentLocation = ValueNotifier<String?>(null);

  // go_router's own Page.name is the RAW route template ('/messages/:requestId'),
  // never the resolved location -- see go_router's builder.dart, which sets
  // `name: state.name ?? state.path`. The actual matched values live in
  // Page.arguments (state.pathParameters), so the resolved location has to be
  // rebuilt by substituting each ':param' segment in the template.
  void _record(Route<dynamic>? route) {
    final settings = route?.settings;
    final template = settings?.name;
    if (template == null || template.isEmpty) return;
    final args = settings!.arguments;
    if (args is! Map) {
      currentLocation.value = template;
      return;
    }
    var resolved = template;
    for (final entry in args.entries) {
      resolved = resolved.replaceAll(':${entry.key}', '${entry.value}');
    }
    currentLocation.value = resolved;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _record(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _record(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _record(newRoute);
}

final currentLocationObserver = CurrentLocationObserver();

/// Built exactly ONCE per ProviderContainer. Nothing in this body may
/// `ref.watch` -- see [GoRouterRefreshStream] for why a rebuild here is a
/// navigation-resetting bug rather than a refresh.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshStream = GoRouterRefreshStream(Supabase.instance.client.auth.onAuthStateChange);
  ref.onDispose(refreshStream.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshStream,
    observers: [currentLocationObserver],
    redirect: (context, state) {
      final hasSession = Supabase.instance.client.auth.currentSession != null;
      return computeAuthRedirect(hasSession: hasSession, location: state.matchedLocation);
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/', builder: (context, state) => const AuthSelectionScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register/personal',
        builder: (context, state) => const RegistrationPersonalScreen(),
      ),
      GoRoute(
        path: '/register/professional',
        // The design doc requires a bounce back to Step 1 when the
        // negotiatorId extra is missing (deep link, hot restart, or reached
        // without completing Step 1) instead of throwing on the cast.
        redirect: (context, state) => state.extra == null ? '/register/personal' : null,
        builder: (context, state) => RegistrationProfessionalScreen(negotiatorId: state.extra as String),
      ),
      GoRoute(
        path: '/verification-pending',
        builder: (context, state) => const VerificationPendingScreen(),
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const MarketplaceScreen()),
      GoRoute(path: '/my-inventory', builder: (context, state) => const MyInventoryScreen()),
      GoRoute(path: '/post-listing', builder: (context, state) => const PostListingScreen()),
      GoRoute(
        path: '/property/:listingId',
        builder: (context, state) => PropertyDetailScreen(listingId: state.pathParameters['listingId']!),
      ),
      GoRoute(path: '/requirement-board', builder: (context, state) => const RequirementBoardScreen()),
      GoRoute(path: '/my-requirements', builder: (context, state) => const MyRequirementsScreen()),
      GoRoute(path: '/post-requirement', builder: (context, state) => const PostRequirementScreen()),
      GoRoute(
        path: '/requirement-board/:requirementId',
        builder: (context, state) =>
            RequirementDetailScreen(requirementId: state.pathParameters['requirementId']!),
      ),
      GoRoute(
        path: '/property/:listingId/matches',
        builder: (context, state) =>
            MatchesForListingScreen(listingId: state.pathParameters['listingId']!),
      ),
      GoRoute(
        path: '/requirement-board/:requirementId/matches',
        builder: (context, state) =>
            MatchesForRequirementScreen(requirementId: state.pathParameters['requirementId']!),
      ),
      GoRoute(path: '/my-matches', builder: (context, state) => const MyMatchesScreen()),
      GoRoute(path: '/my-requests', builder: (context, state) => const MyRequestsScreen()),
      GoRoute(
        path: '/messages/:requestId',
        builder: (context, state) => ChatScreen(requestId: state.pathParameters['requestId']!),
      ),
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/reviews', builder: (context, state) => const ReviewsScreen()),
      GoRoute(path: '/notifications', builder: (context, state) => const NotificationListScreen()),
      GoRoute(path: '/settings/notification', builder: (context, state) => const NotificationSettingsScreen()),
      GoRoute(path: '/settings/account', builder: (context, state) => const AccountSettingsScreen()),
      GoRoute(path: '/settings/privacy', builder: (context, state) => const PrivacyScreen()),
      GoRoute(path: '/settings/help', builder: (context, state) => const HelpScreen()),
      GoRoute(path: '/settings/subscription', builder: (context, state) => const SubscriptionScreen()),
    ],
  );
});
