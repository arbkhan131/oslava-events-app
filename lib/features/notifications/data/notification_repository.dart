import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/bootstrap.dart';
import '../../../core/config/app_environment.dart';
import '../domain/app_notification.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => SupabaseNotificationRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(appEnvironmentProvider),
  ),
);

abstract interface class NotificationRepository {
  Future<List<AppNotification>> loadNotifications({int limit = 50});

  Future<int> loadUnreadCount();

  Future<bool> markRead(String notificationId);

  Future<String> registerDeviceToken({
    required String token,
    required String platform,
    String? deviceId,
  });

  Future<bool> invalidateDeviceToken(String token);
}

class SupabaseNotificationRepository implements NotificationRepository {
  const SupabaseNotificationRepository(this._client, this._environment);

  final SupabaseClient _client;
  final AppEnvironment _environment;

  @override
  Future<List<AppNotification>> loadNotifications({int limit = 50}) async {
    final response = await _client.rpc(
      'list_my_notifications',
      params: {'p_limit': limit},
    );
    return (response as List<dynamic>)
        .map(
          (row) =>
              AppNotification.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<int> loadUnreadCount() async {
    final notifications = await loadNotifications(limit: 100);
    return notifications.where((notification) => !notification.isRead).length;
  }

  @override
  Future<bool> markRead(String notificationId) async {
    final response = await _client.rpc(
      'mark_notification_read',
      params: {'p_notification_id': notificationId},
    );
    return response as bool;
  }

  @override
  Future<String> registerDeviceToken({
    required String token,
    required String platform,
    String? deviceId,
  }) async {
    final response = await _client.rpc(
      'register_device_token',
      params: {
        'p_token': token,
        'p_platform': platform,
        'p_device_id': deviceId,
        'p_app_environment': _environment.name.name,
      },
    );
    return response as String;
  }

  @override
  Future<bool> invalidateDeviceToken(String token) async {
    final response = await _client.rpc(
      'invalidate_device_token',
      params: {'p_token': token},
    );
    return response as bool;
  }
}
