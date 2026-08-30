import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/brutalist_card.dart';
import 'settings_providers.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  // Optimistic local overrides so each switch's thumb moves the instant
  // it's tapped, rather than waiting on write+invalidate+refetch. Each is
  // cleared once that field's write settles (success or failure); on
  // failure the provider's last-known value is what the switch reverts to.
  bool? _matchOverride;
  bool? _messageOverride;
  bool? _cobrokeOverride;

  Future<void> _toggle({
    bool? notifyMatch,
    bool? notifyMessage,
    bool? notifyCobrokeRequest,
  }) async {
    final negotiatorId = ref.read(currentNegotiatorIdProvider);
    if (negotiatorId == null) return;

    setState(() {
      if (notifyMatch != null) _matchOverride = notifyMatch;
      if (notifyMessage != null) _messageOverride = notifyMessage;
      if (notifyCobrokeRequest != null) _cobrokeOverride = notifyCobrokeRequest;
    });

    try {
      await ref.read(settingsRepositoryProvider).updateNotificationPreferences(
            negotiatorId: negotiatorId,
            notifyMatch: notifyMatch,
            notifyMessage: notifyMessage,
            notifyCobrokeRequest: notifyCobrokeRequest,
          );
      // Await the refetch itself, not just fire ref.invalidate -- otherwise
      // clearing the override here races the stale cached value that
      // AsyncValue.when renders during the refetch window (riverpod 2.6.1
      // defaults skipLoadingOnRefresh to true), and the switch visibly
      // bounces back to the pre-tap value before landing on the real one.
      ref.invalidate(notificationPreferencesProvider);
      try {
        await ref.read(notificationPreferencesProvider.future);
      } catch (_) {
        // A refetch failure after a successful write shouldn't surface as
        // a write error -- the write already succeeded.
      }
      if (mounted) {
        setState(() {
          if (notifyMatch != null) _matchOverride = null;
          if (notifyMessage != null) _messageOverride = null;
          if (notifyCobrokeRequest != null) _cobrokeOverride = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (notifyMatch != null) _matchOverride = null;
          if (notifyMessage != null) _messageOverride = null;
          if (notifyCobrokeRequest != null) _cobrokeOverride = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('listing_error_generic'.tr())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          padding: const EdgeInsets.all(20),
          children: [
            BrutalistCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text('notification_settings_match_label'.tr()),
                    value: _matchOverride ?? prefs.notifyMatch,
                    onChanged: (value) => _toggle(notifyMatch: value),
                  ),
                  SwitchListTile(
                    title: Text('notification_settings_message_label'.tr()),
                    value: _messageOverride ?? prefs.notifyMessage,
                    onChanged: (value) => _toggle(notifyMessage: value),
                  ),
                  SwitchListTile(
                    title: Text('notification_settings_cobroke_request_label'.tr()),
                    value: _cobrokeOverride ?? prefs.notifyCobrokeRequest,
                    onChanged: (value) => _toggle(notifyCobrokeRequest: value),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
