/// A foreground 'message' push is redundant when the recipient already has
/// that exact chat open -- ChatScreen's Realtime stream already shows it
/// live. match/cobroke_request pushes are never suppressed: neither has a
/// Realtime-backed screen behind it, so the banner is the only signal the
/// recipient gets.
bool shouldSuppressForegroundBanner({
  required String category,
  required String? currentRouteLocation,
  required Map<String, String> data,
}) {
  if (category != 'message' || currentRouteLocation == null) return false;
  return currentRouteLocation == '/messages/${data['request_id']}';
}
