import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../auth/application/auth_session.dart';
import '../data/fcm_device_token_service.dart';
import '../data/notification_repository.dart';
import '../domain/app_notification.dart';
import '../../../core/widgets/app_feedback.dart';

final alertsProvider = FutureProvider.autoDispose<List<AppNotification>>(
  (ref) => ref.watch(notificationRepositoryProvider).loadNotifications(),
);

final unreadAlertsProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(notificationRepositoryProvider).loadUnreadCount(),
);

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          IconButton(
            tooltip: 'Enable push notifications',
            onPressed: () => _enablePush(context, ref),
            icon: const Icon(Icons.notifications_active),
          ),
        ],
      ),
      body: SafeArea(
        child: alerts.when(
          data: (items) {
            if (items.isEmpty) {
              return RefreshIndicator(
                onRefresh: () => ref.refresh(alertsProvider.future),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    AppEmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'You’re all caught up',
                      message: 'Event updates and team announcements will appear here.',
                      action: OutlinedButton.icon(
                        onPressed: () => _enablePush(context, ref),
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text('Enable notifications'),
                      ),
                    ),
                  ],
                ),
              );
            }

            final unreadCount = items.where((item) => !item.isRead).length;
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(alertsProvider);
                await ref.read(alertsProvider.future);
              },
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _NotificationPolicyCard(unreadCount: unreadCount);
                  }
                  return _AlertTile(alert: items[index - 1]);
                },
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemCount: items.length + 1,
              ),
            );
          },
          error: (error, stackTrace) => ListView(
            children: [
              AppEmptyState(
                icon: Icons.wifi_off_rounded,
                title: 'Couldn’t load alerts',
                message: 'Check your connection and try again.',
                action: FilledButton(
                  onPressed: () => ref.invalidate(alertsProvider),
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Future<void> _enablePush(BuildContext context, WidgetRef ref) async {
    try {
      final token = await ref
          .read(fcmDeviceTokenServiceProvider)
          .registerCurrentDevice();
      if (!context.mounted) {
        return;
      }
      final message = token == null
          ? 'Notifications aren’t ready yet. Check notification permission in your phone settings and try again.'
          : 'Push notifications enabled';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Couldn’t enable notifications. Check your connection and phone notification settings.',
          ),
        ),
      );
    }
  }
}

class _AlertTile extends ConsumerWidget {
  const _AlertTile({required this.alert});

  final AppNotification alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        leading: CircleAvatar(
          backgroundColor: alert.isRead
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            alert.isRead
                ? Icons.notifications_none
                : Icons.notifications_active_outlined,
          ),
        ),
        title: Text(
          alert.title,
          style: TextStyle(
            fontWeight: alert.isRead ? FontWeight.w500 : FontWeight.w700,
          ),
        ),
        subtitle: Text('${alert.body}\n${alert.createdLabel}'),
        isThreeLine: true,
        onTap: () async {
          try {
            await ref.read(notificationRepositoryProvider).markRead(alert.id);
            ref.invalidate(alertsProvider);
            ref.invalidate(unreadAlertsProvider);
            invalidateUserData(ref);
            final session = ref.read(authSessionProvider);
            final roleHomePath = session?.role.homePath ?? '/worker';
            final path = notificationTargetPath(
              notification: alert,
              roleHomePath: roleHomePath,
            );
            if (context.mounted) {
              context.go(path);
            }
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Couldn’t open this alert. Please try again.'),
                ),
              );
            }
          }
        },
      ),
    );
  }
}

class _NotificationPolicyCard extends StatelessWidget {
  const _NotificationPolicyCard({required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              unreadCount == 1
                  ? '1 unread alert'
                  : '$unreadCount unread alerts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'During quiet hours, updates still appear here. Phone notifications arrive when quiet hours end.',
            ),
          ],
        ),
      ),
    );
  }
}
