import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/notification_preferences.dart';
import 'settings_providers.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    NotificationPreferences current, {
    bool? notifyMatch,
    bool? notifyMessage,
    bool? notifyCobrokeRequest,
  }) async {
    final negotiatorId = ref.read(currentNegotiatorIdProvider);
    if (negotiatorId == null) return;
    try {
      await ref.read(settingsRepositoryProvider).updateNotificationPreferences(
            negotiatorId: negotiatorId,
            notifyMatch: notifyMatch ?? current.notifyMatch,
            notifyMessage: notifyMessage ?? current.notifyMessage,
            notifyCobrokeRequest: notifyCobrokeRequest ?? current.notifyCobrokeRequest,
          );
      ref.invalidate(notificationPreferencesProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('listing_error_generic'.tr())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      appBar: AppBar(title: Text('notification_settings_title'.tr())),
      body: prefsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('listing_error_generic'.tr()),
              TextButton(
                onPressed: () => ref.invalidate(notificationPreferencesProvider),
                child: Text('agreement_retry'.tr()),
              ),
            ],
          ),
        ),
        data: (prefs) => ListView(
          children: [
            SwitchListTile(
              title: Text('notification_settings_match_label'.tr()),
              value: prefs.notifyMatch,
              onChanged: (value) => _toggle(context, ref, prefs, notifyMatch: value),
            ),
            SwitchListTile(
              title: Text('notification_settings_message_label'.tr()),
              value: prefs.notifyMessage,
              onChanged: (value) => _toggle(context, ref, prefs, notifyMessage: value),
            ),
            SwitchListTile(
              title: Text('notification_settings_cobroke_request_label'.tr()),
              value: prefs.notifyCobrokeRequest,
              onChanged: (value) => _toggle(context, ref, prefs, notifyCobrokeRequest: value),
            ),
          ],
        ),
      ),
    );
  }
}
