/// Pure mapping from a push's category + data payload to the in-app route
/// to open on tap. `data` mirrors PushPayload.deepLinkData / a
/// RemoteMessage's .data map (string values only, per FCM's own payload
/// format).
String deepLinkRouteFor(String category, Map<String, String> data) {
  switch (category) {
    case 'match':
      if (data['owner_side'] == 'listing') {
        return '/property/${data['listing_id']}/matches';
      }
      return '/requirement-board/${data['requirement_id']}/matches';
    case 'cobroke_request':
      return '/my-requests';
    case 'message':
      return '/messages/${data['request_id']}';
    default:
      return '/home';
  }
}

/// The 4 branch paths owned by app_router.dart's
/// StatefulShellRoute.indexedStack. Kept here next to deepLinkRouteFor
/// because its `default` arm returns one of them ('/home'), and how a caller
/// navigates to a route depends entirely on which side of this line it falls:
///
/// - shell-branch path -> `go`. A `push` would mount a SECOND MainShell (and
///   a second bottom nav bar) on top of the live one.
/// - anything else -> `push`. Every other route deepLinkRouteFor returns
///   ('/messages/:id', '/property/:id/matches', '/my-requests',
///   '/requirement-board/:id/matches') is a flat top-level route OUTSIDE the
///   shell; a `go` there would tear down the whole shell -- all 4 branches
///   and their back-stacks -- leaving the negotiator on a bare screen with no
///   bottom nav and nothing to pop back to.
const shellBranchRoutes = {'/home', '/marketplace', '/chat', '/profile'};

/// Whether `route` is one of app_router.dart's shell branch paths (see
/// [shellBranchRoutes]) and must therefore be navigated to with `go`, not
/// `push`.
bool isShellBranchRoute(String route) => shellBranchRoutes.contains(route);
