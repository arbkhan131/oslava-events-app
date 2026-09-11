import '../../events/domain/event_summary.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.relatedEventId,
    this.deepLinkPath,
    this.readAt,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final String? relatedEventId;
  final String? deepLinkPath;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  static AppNotification fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['notification_id'] as String? ?? json['id'] as String,
      type: NotificationType.fromDatabase(json['notification_type'] as String),
      title: json['title'] as String,
      body: json['body'] as String,
      relatedEventId: json['related_event_id'] as String?,
      deepLinkPath: json['deep_link_path'] as String?,
      readAt: json['read_at'] == null
          ? null
          : DateTime.parse(json['read_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  String get createdLabel => formatKolkataDateTime12h(createdAt);
}

enum NotificationType {
  newEvent,
  tierOpened,
  applicationConfirmed,
  waitlistJoined,
  waitlistPromoted,
  captainAssigned,
  supervisorAssigned,
  eventFull,
  eventUpdated,
  eventCancelled,
  reportingReminder,
  categoryChanged,
  accountDetained,
  vacancyReopened;

  static NotificationType fromDatabase(String value) {
    switch (value) {
      case 'NEW_EVENT':
        return NotificationType.newEvent;
      case 'TIER_OPENED':
        return NotificationType.tierOpened;
      case 'APPLICATION_CONFIRMED':
        return NotificationType.applicationConfirmed;
      case 'WAITLIST_JOINED':
        return NotificationType.waitlistJoined;
      case 'WAITLIST_PROMOTED':
        return NotificationType.waitlistPromoted;
      case 'CAPTAIN_ASSIGNED':
        return NotificationType.captainAssigned;
      case 'SUPERVISOR_ASSIGNED':
        return NotificationType.supervisorAssigned;
      case 'EVENT_FULL':
        return NotificationType.eventFull;
      case 'EVENT_UPDATED':
        return NotificationType.eventUpdated;
      case 'EVENT_CANCELLED':
        return NotificationType.eventCancelled;
      case 'REPORTING_REMINDER':
        return NotificationType.reportingReminder;
      case 'CATEGORY_CHANGED':
        return NotificationType.categoryChanged;
      case 'ACCOUNT_DETAINED':
        return NotificationType.accountDetained;
      case 'VACANCY_REOPENED':
        return NotificationType.vacancyReopened;
      default:
        throw FormatException('Unknown notification type "$value".');
    }
  }

  String get databaseValue {
    switch (this) {
      case NotificationType.newEvent:
        return 'NEW_EVENT';
      case NotificationType.tierOpened:
        return 'TIER_OPENED';
      case NotificationType.applicationConfirmed:
        return 'APPLICATION_CONFIRMED';
      case NotificationType.waitlistJoined:
        return 'WAITLIST_JOINED';
      case NotificationType.waitlistPromoted:
        return 'WAITLIST_PROMOTED';
      case NotificationType.captainAssigned:
        return 'CAPTAIN_ASSIGNED';
      case NotificationType.supervisorAssigned:
        return 'SUPERVISOR_ASSIGNED';
      case NotificationType.eventFull:
        return 'EVENT_FULL';
      case NotificationType.eventUpdated:
        return 'EVENT_UPDATED';
      case NotificationType.eventCancelled:
        return 'EVENT_CANCELLED';
      case NotificationType.reportingReminder:
        return 'REPORTING_REMINDER';
      case NotificationType.categoryChanged:
        return 'CATEGORY_CHANGED';
      case NotificationType.accountDetained:
        return 'ACCOUNT_DETAINED';
      case NotificationType.vacancyReopened:
        return 'VACANCY_REOPENED';
    }
  }
}

String notificationTargetPath({
  required AppNotification notification,
  required String roleHomePath,
}) {
  final explicit = notification.deepLinkPath?.trim();
  if (explicit != null && explicit.startsWith('/')) {
    return explicit;
  }

  final eventId = notification.relatedEventId;
  if (eventId != null && eventId.trim().isNotEmpty) {
    if (roleHomePath == '/worker') {
      return '/worker/events/$eventId';
    }
    return '$roleHomePath/events/$eventId';
  }

  return '$roleHomePath/alerts';
}
