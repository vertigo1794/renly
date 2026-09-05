import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import 'fcm_token_repository.dart';
import 'models/app_notification.dart';
import 'notification_repository.dart';
import 'push_notification_repository.dart';

final fcmTokenRepositoryProvider = Provider<FcmTokenRepository>((ref) {
  return FcmTokenRepository(Supabase.instance.client);
});

final pushNotificationRepositoryProvider = Provider<PushNotificationRepository>((ref) {
  return PushNotificationRepository(Supabase.instance.client);
});

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(Supabase.instance.client);
});

/// Same session-state read duplicated across every feature's own
/// providers file in this project (see the identical copies in
/// listing_providers.dart / cobroke_request_providers.dart) -- established
/// convention, not an oversight.
final _currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

/// autoDispose + refetch-on-entry -- there is no push-driven client-side
/// cache invalidation to hook into, same reasoning as
/// receivedRequestsProvider/sentRequestsProvider in cobroke_request_providers.dart.
final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) {
  final recipientId = ref.watch(_currentNegotiatorIdProvider);
  if (recipientId == null) return Future.value(const []);
  return ref.watch(notificationRepositoryProvider).fetchNotifications(recipientId);
});

/// Derives from notificationsProvider's already-fetched list rather than a
/// second query -- the list is capped to 50 recent rows, small enough that
/// a client-side count is simpler than a dedicated count query.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final notificationsAsync = ref.watch(notificationsProvider);
  return notificationsAsync.valueOrNull?.where((n) => n.readAt == null).length ?? 0;
});
