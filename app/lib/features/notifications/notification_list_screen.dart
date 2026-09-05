import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_card.dart';
import 'deep_link.dart';
import 'notification_providers.dart';

class NotificationListScreen extends ConsumerWidget {
  const NotificationListScreen({super.key});

  IconData _iconFor(String category) {
    switch (category) {
      case 'match':
        return PhosphorIcons.handshake(PhosphorIconsStyle.bold);
      case 'cobroke_request':
        return PhosphorIcons.userPlus(PhosphorIconsStyle.bold);
      case 'message':
      default:
        return PhosphorIcons.chatCircle(PhosphorIconsStyle.bold);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('notification_center_title'.tr())),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
        data: (notifications) {
          if (notifications.isEmpty) {
            return Center(child: Text('notification_center_empty'.tr()));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notification = notifications[index];
              final isUnread = notification.readAt == null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (isUnread) {
                        // Best-effort: mark-read runs in the background so a
                        // failure (offline, backend hiccup) never blocks the
                        // negotiator from opening the deep-linked screen.
                        unawaited(() async {
                          try {
                            await ref.read(notificationRepositoryProvider).markRead(notification.notificationId);
                            ref.invalidate(notificationsProvider);
                          } catch (e) {
                            debugPrint('markRead failed: $e');
                          }
                        }());
                      }
                      context.push(deepLinkRouteFor(notification.category, notification.deepLinkData));
                    },
                    child: BrutalistCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(_iconFor(notification.category)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  notification.title,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(notification.body),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
