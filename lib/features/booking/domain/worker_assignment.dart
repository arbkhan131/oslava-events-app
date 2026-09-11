import '../../events/domain/event_summary.dart';
import 'waitlist_result.dart';

enum AssignmentStatus {
  confirmed,
  cancelled,
  removed,
  completed;

  static AssignmentStatus fromDatabase(String value) {
    switch (value) {
      case 'CONFIRMED':
        return AssignmentStatus.confirmed;
      case 'CANCELLED':
        return AssignmentStatus.cancelled;
      case 'REMOVED':
        return AssignmentStatus.removed;
      case 'COMPLETED':
        return AssignmentStatus.completed;
      default:
        throw FormatException('Unknown assignment status "$value".');
    }
  }
}

class WorkerAssignment {
  const WorkerAssignment({
    required this.assignmentId,
    required this.eventId,
    required this.title,
    required this.venueName,
    required this.reportingAt,
    required this.expectedEndsAt,
    required this.status,
    required this.cancellationDeadlineAt,
    required this.canCancel,
  });

  final String assignmentId;
  final String eventId;
  final String title;
  final String venueName;
  final DateTime reportingAt;
  final DateTime expectedEndsAt;
  final AssignmentStatus status;
  final DateTime cancellationDeadlineAt;
  final bool canCancel;

  static WorkerAssignment fromJson(Map<String, dynamic> json) {
    return WorkerAssignment(
      assignmentId: json['assignment_id'] as String,
      eventId: json['event_id'] as String,
      title: json['title'] as String,
      venueName: json['venue_name'] as String,
      reportingAt: DateTime.parse(json['reporting_at'] as String),
      expectedEndsAt: DateTime.parse(json['expected_ends_at'] as String),
      status: AssignmentStatus.fromDatabase(
        json['assignment_status'] as String,
      ),
      cancellationDeadlineAt: DateTime.parse(
        json['cancellation_deadline_at'] as String,
      ),
      canCancel: json['can_cancel'] as bool,
    );
  }

  String get reportingLabel => formatKolkataDateTime12h(reportingAt);
}

class CancellationResult {
  const CancellationResult({
    required this.cancellationId,
    required this.assignmentId,
    required this.eventId,
    required this.status,
    required this.recruitmentStatus,
    this.promotedAssignmentId,
  });

  final String cancellationId;
  final String assignmentId;
  final String eventId;
  final AssignmentStatus status;
  final RecruitmentStatus recruitmentStatus;
  final String? promotedAssignmentId;

  static CancellationResult fromJson(Map<String, dynamic> json) {
    return CancellationResult(
      cancellationId: json['cancellation_id'] as String,
      assignmentId: json['assignment_id'] as String,
      eventId: json['event_id'] as String,
      status: AssignmentStatus.fromDatabase(json['status'] as String),
      promotedAssignmentId: json['promoted_assignment_id'] as String?,
      recruitmentStatus: RecruitmentStatus.fromDatabase(
        json['recruitment_status'] as String,
      ),
    );
  }
}

class WorkerWaitlistEntry {
  const WorkerWaitlistEntry({
    required this.waitlistEntryId,
    required this.eventId,
    required this.title,
    required this.venueName,
    required this.reportingAt,
    required this.expectedEndsAt,
    required this.status,
    required this.canWithdraw,
    this.queuePosition,
  });

  final String waitlistEntryId;
  final String eventId;
  final String title;
  final String venueName;
  final DateTime reportingAt;
  final DateTime expectedEndsAt;
  final WaitlistEntryStatus status;
  final int? queuePosition;
  final bool canWithdraw;

  static WorkerWaitlistEntry fromJson(Map<String, dynamic> json) {
    return WorkerWaitlistEntry(
      waitlistEntryId: json['waitlist_entry_id'] as String,
      eventId: json['event_id'] as String,
      title: json['title'] as String,
      venueName: json['venue_name'] as String,
      reportingAt: DateTime.parse(json['reporting_at'] as String),
      expectedEndsAt: DateTime.parse(json['expected_ends_at'] as String),
      status: WaitlistEntryStatus.fromDatabase(json['status'] as String),
      queuePosition: (json['queue_position'] as num?)?.toInt(),
      canWithdraw: json['can_withdraw'] as bool? ?? false,
    );
  }

  String get reportingLabel => formatKolkataDateTime12h(reportingAt);
}
