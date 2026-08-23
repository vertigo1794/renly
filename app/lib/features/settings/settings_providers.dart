import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import 'models/identity_info.dart';
import 'models/notification_preferences.dart';
import 'settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(Supabase.instance.client);
});

/// Same session-state read as the copies in every sibling feature's own
/// providers file -- duplicated here rather than imported, same
/// established reasoning as those files.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

/// autoDispose is REQUIRED, not the default, in this project's pinned
/// Riverpod version (2.6.1).
final notificationPreferencesProvider = FutureProvider.autoDispose<NotificationPreferences>((ref) {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) {
    return Future.error(StateError('No authenticated negotiator.'));
  }
  return ref.watch(settingsRepositoryProvider).fetchNotificationPreferences(negotiatorId);
});

final identityInfoProvider = FutureProvider.autoDispose<IdentityInfo>((ref) {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) {
    return Future.error(StateError('No authenticated negotiator.'));
  }
  return ref.watch(settingsRepositoryProvider).fetchIdentityInfo(negotiatorId);
});
