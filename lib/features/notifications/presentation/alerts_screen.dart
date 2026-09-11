import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../auth/application/auth_session.dart';
import '../data/fcm_device_token_service.dart';
import '../data/notification_repository.dart';
import '../domain/app_notification.dart';

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
              return const Center(child: Text('No alerts yet'));
            }

            final unreadCount = items.where((item) => !item.isRead).length;
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(alertsProvider),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _NotificationPolicyCard(unreadCount: unreadCount);
                  }
                  return _AlertTile(alert: items[index - 1]);
                },
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemCount: items.length + 1,
              ),
            );
          },
          error: (error, stackTrace) => Center(child: Text(error.toString())),
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
          ? 'No FCM token was returned for this device'
          : 'Push notifications enabled';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Push setup unavailable: $error')));
    }
  }
}

class _AlertTile extends ConsumerWidget {
  const _AlertTile({required this.alert});

  final AppNotification alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(alert.isRead ? Icons.notifications_none : Icons.circle),
      title: Text(alert.title),
      subtitle: Text('${alert.body}\n${alert.createdLabel}'),
      isThreeLine: true,
      onTap: () async {
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
      },
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
              'Quiet hours are handled by the server. During quiet hours, app alerts remain visible here while push delivery waits for the next allowed window.',
            ),
          ],
        ),
      ),
    );
  }
}
