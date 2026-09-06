import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/auth_selection_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/onboarding_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/auth/registration_personal_screen.dart';
import '../../features/auth/registration_professional_screen.dart';
import '../../features/auth/verification_pending_screen.dart';
import '../../features/collaboration/chat_screen.dart';
import '../../features/collaboration/conversation_list_screen.dart';
import '../../features/collaboration/message_providers.dart' hide currentNegotiatorIdProvider;
import '../../features/collaboration/my_requests_screen.dart';
import '../../features/home/main_dashboard_screen.dart';
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

  // The StatefulShellRoute wrapping the 4 bottom-nav branches has no `name`
  // and no `path` of its own, so go_router's builder.dart gives its page
  // `name: state.name ?? state.path` == null. That makes the shell page
  // INVISIBLE to [_record]'s null-name guard below: popping back onto the
  // shell from a root-level pushed route (e.g. '/messages/req-1') would
  // otherwise leave [currentLocation] stuck on the popped route, and a
  // foreground push for that same chat would be wrongly suppressed while
  // the user is actually sitting on a bottom-nav tab.
  //
  // [MainShell] therefore reports its own Route object plus the active
  // branch's path here on every build; [_record] recognises that exact Route
  // by identity (never by name) and substitutes the branch path. A
  // WeakReference is used so a discarded shell (e.g. after sign-out) is not
  // retained by this app-lifetime singleton.
  WeakReference<Route<dynamic>>? _shellRouteRef;
  String? _shellBranchLocation;

  /// Called by [MainShell] on every build. [shellRoute] is the shell's own
  /// route on the ROOT navigator; [location] is the active branch's path
  /// ('/home', '/marketplace', '/chat' or '/profile').
  ///
  /// The branch is always remembered (so a later pop back onto the shell can
  /// restore it), but [currentLocation] is only updated when the shell is
  /// actually the topmost route -- while it is buried under a pushed route
  /// such as '/messages/:requestId', that pushed route is what the user is
  /// looking at and must not be clobbered.
  void recordShellBranch({required Route<dynamic>? shellRoute, required String location}) {
    _shellRouteRef = shellRoute == null ? null : WeakReference<Route<dynamic>>(shellRoute);
    _shellBranchLocation = location;
    if (shellRoute == null || shellRoute.isCurrent) currentLocation.value = location;
  }

  // go_router's own Page.name is the RAW route template ('/messages/:requestId'),
  // never the resolved location -- see go_router's builder.dart, which sets
  // `name: state.name ?? state.path`. The actual matched values live in
  // Page.arguments (state.pathParameters), so the resolved location has to be
  // rebuilt by substituting each ':param' segment in the template.
  void _record(Route<dynamic>? route) {
    // The shell's own (unnamed) route is resolved by identity, BEFORE the
    // null-name guard -- which stays fully intact for every other route.
    if (route != null && identical(route, _shellRouteRef?.target)) {
      final shellLocation = _shellBranchLocation;
      if (shellLocation != null) currentLocation.value = shellLocation;
      return;
    }
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
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell, locationObserver: currentLocationObserver),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (context, state) => const MainDashboardScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/marketplace', builder: (context, state) => const MarketplaceScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/chat', builder: (context, state) => const ConversationListScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen())],
          ),
        ],
      ),
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

/// The Scaffold shared by all 4 bottom-nav branches (Home/Market/Chat/
/// Profile): hosts the [StatefulNavigationShell]'s IndexedStack body, the
/// bottom nav bar (tapping a destination calls [StatefulNavigationShell.
/// goBranch], which preserves each branch's own navigation stack), and the
/// centered Post FAB shortcut to `/post-listing`.
///
/// It also reports the active branch's path to [locationObserver] on every
/// build -- see [CurrentLocationObserver.recordShellBranch] for why the
/// observer cannot work this out from the shell page alone.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell, required this.locationObserver});

  final StatefulNavigationShell navigationShell;
  final CurrentLocationObserver locationObserver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read during build (the Route is only reachable from this context), but
    // report AFTER the frame: at build time the Navigator stack may not yet
    // reflect a route being pushed on top of the shell in this same frame,
    // so `isCurrent` would be read too early.
    final branchPath = navigationShell.route.branches[navigationShell.currentIndex].defaultRoute?.path;
    final shellRoute = ModalRoute.of(context);
    if (branchPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        locationObserver.recordShellBranch(shellRoute: shellRoute, location: branchPath);
      });
    }

    final hasUnreadAsync = ref.watch(hasUnreadMessagesProvider);

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: _FloatingDock(
            currentIndex: navigationShell.currentIndex,
            onTap: navigationShell.goBranch,
            hasUnreadChat: hasUnreadAsync.maybeWhen(data: (value) => value, orElse: () => false),
            onPost: () => context.push('/post-listing'),
          ),
        ),
      ),
    );
  }
}

/// The floating "ultra-stylish" glass dock replacing the standard
/// BottomNavigationBar+FAB pair, matching the Stitch
/// "Renly - Bottom Nav Dock (Ultra-Stylish)" mockup exactly: a dark
/// translucent capsule with 4 tabs and an elevated lime "+" button
/// floating above its center. [hasUnreadChat] backs the Chat tab's
/// presence dot -- real data (MessageRepository.hasUnreadMessages), never
/// always-on decoration.
class _FloatingDock extends StatelessWidget {
  const _FloatingDock({
    required this.currentIndex,
    required this.onTap,
    required this.hasUnreadChat,
    required this.onPost,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool hasUnreadChat;
  final VoidCallback onPost;

  static const _capsuleColor = Color(0xF0121214);
  static const _lime = Color(0xFFD4FF00);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: _capsuleColor,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _DockItem(
              icon: PhosphorIcons.house(PhosphorIconsStyle.bold),
              label: 'nav_home'.tr(),
              active: currentIndex == 0,
              onTap: () => onTap(0),
            ),
          ),
          Expanded(
            child: _DockItem(
              icon: PhosphorIcons.storefront(PhosphorIconsStyle.bold),
              label: 'nav_market'.tr(),
              active: currentIndex == 1,
              onTap: () => onTap(1),
            ),
          ),
          _DockPostButton(onTap: onPost),
          Expanded(
            child: _DockItem(
              icon: PhosphorIcons.chatCircle(PhosphorIconsStyle.bold),
              label: 'nav_chat'.tr(),
              active: currentIndex == 2,
              onTap: () => onTap(2),
              showDot: hasUnreadChat,
            ),
          ),
          Expanded(
            child: _DockItem(
              icon: PhosphorIcons.user(PhosphorIconsStyle.bold),
              label: 'nav_profile'.tr(),
              active: currentIndex == 3,
              onTap: () => onTap(3),
            ),
          ),
        ],
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.showDot = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: active ? _FloatingDock._lime : const Color(0xFF9CA3AF)),
                ),
                if (showDot)
                  Positioned(
                    top: -2,
                    right: 2,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: _FloatingDock._lime,
                        shape: BoxShape.circle,
                        border: Border.all(color: _FloatingDock._capsuleColor, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockPostButton extends StatelessWidget {
  const _DockPostButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Transform.translate(
        offset: const Offset(0, -18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _FloatingDock._lime,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.black, width: 2),
                  boxShadow: [
                    BoxShadow(color: _FloatingDock._lime.withValues(alpha: 0.45), blurRadius: 24, spreadRadius: 2),
                  ],
                ),
                child: Icon(PhosphorIcons.plus(PhosphorIconsStyle.bold), color: Colors.black, size: 28),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'nav_post'.tr().toUpperCase(),
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: _FloatingDock._lime,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
