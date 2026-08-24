import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fcm_token_repository.dart';
import 'push_notification_repository.dart';

final fcmTokenRepositoryProvider = Provider<FcmTokenRepository>((ref) {
  return FcmTokenRepository(Supabase.instance.client);
});

final pushNotificationRepositoryProvider = Provider<PushNotificationRepository>((ref) {
  return PushNotificationRepository(Supabase.instance.client);
});
