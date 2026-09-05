/// Pure relative-time-display formatting for the dashboard's Recent
/// Listings feed. No Flutter/Supabase -- fully unit-testable, same style
/// as ListingFormatting/RequirementFormatting.
class DashboardFormatting {
  DashboardFormatting._();

  static String formatRelativeTime(DateTime createdAt, DateTime now) {
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
