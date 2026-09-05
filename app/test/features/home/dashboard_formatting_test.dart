import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/home/dashboard_formatting.dart';

void main() {
  final now = DateTime(2026, 1, 1, 12, 0, 0);

  test('formats under a minute as "just now"', () {
    final createdAt = now.subtract(const Duration(seconds: 30));
    expect(DashboardFormatting.formatRelativeTime(createdAt, now), 'just now');
  });

  test('formats minutes ago', () {
    final createdAt = now.subtract(const Duration(minutes: 18));
    expect(DashboardFormatting.formatRelativeTime(createdAt, now), '18m ago');
  });

  test('formats hours ago', () {
    final createdAt = now.subtract(const Duration(hours: 2));
    expect(DashboardFormatting.formatRelativeTime(createdAt, now), '2h ago');
  });

  test('formats days ago', () {
    final createdAt = now.subtract(const Duration(days: 3));
    expect(DashboardFormatting.formatRelativeTime(createdAt, now), '3d ago');
  });

  test('boundary: exactly 60 minutes rolls over to hours', () {
    final createdAt = now.subtract(const Duration(minutes: 60));
    expect(DashboardFormatting.formatRelativeTime(createdAt, now), '1h ago');
  });

  test('boundary: exactly 24 hours rolls over to days', () {
    final createdAt = now.subtract(const Duration(hours: 24));
    expect(DashboardFormatting.formatRelativeTime(createdAt, now), '1d ago');
  });
}
