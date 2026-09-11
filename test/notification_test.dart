import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/app/router/app_router.dart';
import 'package:oslava_events/features/auth/application/auth_session.dart';
import 'package:oslava_events/features/notifications/domain/app_notification.dart';

void main() {
  group('Phase 14 notification models', () {
    test('parses in-app notification rows', () {
      final notification = AppNotification.fromJson({
        'notification_id': 'notification-id',
        'notification_type': 'REPORTING_REMINDER',
        'title': '2h reporting reminder',
        'body': 'Reporting time is approaching.',
        'related_event_id': 'event-id',
        'deep_link_path': '/worker/work',
        'read_at': null,
        'created_at': '2026-10-10T10:00:00Z',
      });

      expect(notification.id, 'notification-id');
      expect(notification.type, NotificationType.reportingReminder);
      expect(notification.isRead, isFalse);
      expect(notification.deepLinkPath, '/worker/work');
    });

    test('maps all V1 notification enum labels', () {
      for (final type in NotificationType.values) {
        expect(NotificationType.fromDatabase(type.databaseValue), type);
      }
    });

    test('uses explicit authenticated deep links when present', () {
      final notification = AppNotification.fromJson({
        'notification_id': 'notification-id',
        'notification_type': 'EVENT_UPDATED',
        'title': 'Updated',
        'body': 'Schedule changed.',
        'related_event_id': 'event-id',
        'deep_link_path': '/captain/events/event-id',
        'read_at': '2026-10-10T10:15:00Z',
        'created_at': '2026-10-10T10:00:00Z',
      });

      expect(
        notificationTargetPath(
          notification: notification,
          roleHomePath: '/captain',
        ),
        '/captain/events/event-id',
      );
    });

    test('falls back to a role-aware event target without explicit path', () {
      final notification = AppNotification.fromJson({
        'notification_id': 'notification-id',
        'notification_type': 'REPORTING_REMINDER',
        'title': 'Reminder',
        'body': 'Reporting soon.',
        'related_event_id': 'event-id',
        'deep_link_path': null,
        'read_at': null,
        'created_at': '2026-10-10T10:00:00Z',
      });

      expect(
        notificationTargetPath(
          notification: notification,
          roleHomePath: '/worker',
        ),
        '/worker/events/event-id',
      );
      expect(
        notificationTargetPath(
          notification: notification,
          roleHomePath: '/admin',
        ),
        '/admin/events/event-id',
      );
    });
  });

  group('Phase 14 route guards', () {
    test('each authenticated role can open its own Alerts route', () {
      for (final role in AppRole.values) {
        expect(
          roleAwareRedirect(
            isAuthenticated: true,
            role: role,
            location: '${role.homePath}/alerts',
          ),
          isNull,
        );
      }
    });

    test('role guard prevents opening another role Alerts route', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.worker,
          location: '/admin/alerts',
        ),
        '/worker',
      );
    });
  });
}
