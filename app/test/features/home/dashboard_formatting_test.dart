import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/home/dashboard_formatting.dart';

void main() {
  final now = DateTime(2026, 1, 1, 12, 0, 0);

  test('formats under a minute as "just now"', () {
    final createdAt = now.subtract(const Duration(seconds: 30));
    final bucket = DashboardFormatting.relativeTimeBucket(createdAt, now);
    expect(bucket.unit, 'just_now');
    expect(bucket.count, isNull);
  });

  test('formats minutes ago', () {
    final createdAt = now.subtract(const Duration(minutes: 18));
    final bucket = DashboardFormatting.relativeTimeBucket(createdAt, now);
    expect(bucket.unit, 'minutes');
    expect(bucket.count, 18);
  });

  test('formats hours ago', () {
    final createdAt = now.subtract(const Duration(hours: 2));
    final bucket = DashboardFormatting.relativeTimeBucket(createdAt, now);
    expect(bucket.unit, 'hours');
    expect(bucket.count, 2);
  });

  test('formats days ago', () {
    final createdAt = now.subtract(const Duration(days: 3));
    final bucket = DashboardFormatting.relativeTimeBucket(createdAt, now);
    expect(bucket.unit, 'days');
    expect(bucket.count, 3);
  });

  test('boundary: exactly 60 minutes rolls over to hours', () {
    final createdAt = now.subtract(const Duration(minutes: 60));
    final bucket = DashboardFormatting.relativeTimeBucket(createdAt, now);
    expect(bucket.unit, 'hours');
    expect(bucket.count, 1);
  });

  test('boundary: exactly 24 hours rolls over to days', () {
    final createdAt = now.subtract(const Duration(hours: 24));
    final bucket = DashboardFormatting.relativeTimeBucket(createdAt, now);
    expect(bucket.unit, 'days');
    expect(bucket.count, 1);
  });
}
