import 'package:easy_localization/easy_localization.dart';

/// Relative-time-display formatting for the dashboard's Recent Listings
/// feed.
class DashboardFormatting {
  DashboardFormatting._();

  /// Pure, no I18n dependency -- which relative-time bucket `createdAt`
  /// falls into as of `now`, and the raw count for it (null for "just
  /// now", which has no count). This is what's actually unit-tested: the
  /// bucketing/rollover LOGIC (same style as ListingFormatting/
  /// RequirementFormatting, both genuinely pure). [formatRelativeTime]
  /// below resolves a bucket into a real localized string via `.tr()`,
  /// which needs an initialized EasyLocalization instance -- a bare
  /// `test()` unit test has no business depending on that just to verify
  /// "18 minutes ago rounds to the minutes bucket, not hours".
  static ({String unit, int? count}) relativeTimeBucket(DateTime createdAt, DateTime now) {
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 1) return (unit: 'just_now', count: null);
    if (diff.inMinutes < 60) return (unit: 'minutes', count: diff.inMinutes);
    if (diff.inHours < 24) return (unit: 'hours', count: diff.inHours);
    return (unit: 'days', count: diff.inDays);
  }

  static String formatRelativeTime(DateTime createdAt, DateTime now) {
    final bucket = relativeTimeBucket(createdAt, now);
    switch (bucket.unit) {
      case 'just_now':
        return 'dashboard_time_just_now'.tr();
      case 'minutes':
        return 'dashboard_time_minutes_ago'.tr(namedArgs: {'count': '${bucket.count}'});
      case 'hours':
        return 'dashboard_time_hours_ago'.tr(namedArgs: {'count': '${bucket.count}'});
      default:
        return 'dashboard_time_days_ago'.tr(namedArgs: {'count': '${bucket.count}'});
    }
  }
}
