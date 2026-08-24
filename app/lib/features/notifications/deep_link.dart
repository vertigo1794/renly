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
