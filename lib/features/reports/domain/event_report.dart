import '../../attendance/domain/attendance_roster.dart';
import '../../booking/domain/worker_assignment.dart';
import '../../events/domain/event_summary.dart';
import '../../workers/domain/worker_profile.dart';

class EventReportSummary {
  const EventReportSummary({
    required this.eventId,
    required this.title,
    required this.eventType,
    required this.venueName,
    required this.eventDate,
    required this.reportingAt,
    required this.workStartsAt,
    required this.expectedEndsAt,
    required this.requiredWorkerCount,
    required this.confirmedWorkerCount,
    required this.dailyWage,
    required this.allowanceTotal,
    required this.totalWorkerPayDisplay,
    required this.currencyCode,
    required this.eventStatus,
    required this.recruitmentStatus,
    required this.attendanceTotal,
    required this.attendanceNotMarked,
    required this.attendancePresent,
    required this.attendanceLate,
    required this.attendanceAbsent,
  });

  final String eventId;
  final String title;
  final String eventType;
  final String venueName;
  final DateTime eventDate;
  final DateTime reportingAt;
  final DateTime workStartsAt;
  final DateTime expectedEndsAt;
  final int requiredWorkerCount;
  final int confirmedWorkerCount;
  final double dailyWage;
  final double allowanceTotal;
  final double totalWorkerPayDisplay;
  final String currencyCode;
  final EventStatus eventStatus;
  final RecruitmentStatus recruitmentStatus;
  final int attendanceTotal;
  final int attendanceNotMarked;
  final int attendancePresent;
  final int attendanceLate;
  final int attendanceAbsent;

  static EventReportSummary fromJson(Map<String, dynamic> json) {
    return EventReportSummary(
      eventId: json['event_id'] as String,
      title: json['title'] as String,
      eventType: json['event_type'] as String,
      venueName: json['venue_name'] as String,
      eventDate: DateTime.parse(json['event_date'] as String),
      reportingAt: DateTime.parse(json['reporting_at'] as String),
      workStartsAt: DateTime.parse(json['work_starts_at'] as String),
      expectedEndsAt: DateTime.parse(json['expected_ends_at'] as String),
      requiredWorkerCount: (json['required_worker_count'] as num).toInt(),
      confirmedWorkerCount: (json['confirmed_worker_count'] as num).toInt(),
      dailyWage: (json['daily_wage'] as num).toDouble(),
      allowanceTotal: (json['allowance_total'] as num).toDouble(),
      totalWorkerPayDisplay: (json['total_worker_pay_display'] as num)
          .toDouble(),
      currencyCode: json['currency_code'] as String,
      eventStatus: EventStatus.fromDatabase(json['event_status'] as String),
      recruitmentStatus: RecruitmentStatus.fromDatabase(
        json['recruitment_status'] as String,
      ),
      attendanceTotal: (json['attendance_total'] as num).toInt(),
      attendanceNotMarked: (json['attendance_not_marked'] as num).toInt(),
      attendancePresent: (json['attendance_present'] as num).toInt(),
      attendanceLate: (json['attendance_late'] as num).toInt(),
      attendanceAbsent: (json['attendance_absent'] as num).toInt(),
    );
  }
}

class StaffingReportRow {
  const StaffingReportRow({
    required this.assignmentId,
    required this.workerId,
    required this.fullName,
    required this.phoneE164,
    required this.categoryAtConfirmation,
    required this.assignmentStatus,
    required this.confirmedAt,
    required this.attendanceStatus,
    required this.dailyWage,
    required this.allowanceTotal,
    required this.totalPayDisplay,
    required this.currencyCode,
    this.workerNumber,
    this.attendanceMarkedAt,
    this.attendanceNotes,
  });

  final String assignmentId;
  final String workerId;
  final int? workerNumber;
  final String fullName;
  final String phoneE164;
  final WorkerCategory categoryAtConfirmation;
  final AssignmentStatus assignmentStatus;
  final DateTime confirmedAt;
  final AttendanceStatus attendanceStatus;
  final DateTime? attendanceMarkedAt;
  final String? attendanceNotes;
  final double dailyWage;
  final double allowanceTotal;
  final double totalPayDisplay;
  final String currencyCode;

  static StaffingReportRow fromJson(Map<String, dynamic> json) {
    return StaffingReportRow(
      assignmentId: json['assignment_id'] as String,
      workerId: json['worker_id'] as String,
      workerNumber: (json['worker_number'] as num?)?.toInt(),
      fullName: json['full_name'] as String,
      phoneE164: json['phone_e164'] as String,
      categoryAtConfirmation: WorkerCategory.fromDatabase(
        json['category_at_confirmation'] as String?,
      )!,
      assignmentStatus: AssignmentStatus.fromDatabase(
        json['assignment_status'] as String,
      ),
      confirmedAt: DateTime.parse(json['confirmed_at'] as String),
      attendanceStatus: AttendanceStatus.fromDatabase(
        json['attendance_status'] as String,
      ),
      attendanceMarkedAt: json['attendance_marked_at'] == null
          ? null
          : DateTime.parse(json['attendance_marked_at'] as String),
      attendanceNotes: json['attendance_notes'] as String?,
      dailyWage: (json['daily_wage'] as num).toDouble(),
      allowanceTotal: (json['allowance_total'] as num).toDouble(),
      totalPayDisplay: (json['total_pay_display'] as num).toDouble(),
      currencyCode: json['currency_code'] as String,
    );
  }
}

class EventAuditHistoryRow {
  const EventAuditHistoryRow({
    required this.historySource,
    required this.action,
    required this.entityType,
    required this.createdAt,
    this.actorId,
    this.actorRole,
    this.entityId,
    this.reason,
  });

  final String historySource;
  final String action;
  final String? actorId;
  final String? actorRole;
  final String entityType;
  final String? entityId;
  final String? reason;
  final DateTime createdAt;

  static EventAuditHistoryRow fromJson(Map<String, dynamic> json) {
    return EventAuditHistoryRow(
      historySource: json['history_source'] as String,
      action: json['action'] as String,
      actorId: json['actor_id'] as String?,
      actorRole: json['actor_role'] as String?,
      entityType: json['entity_type'] as String,
      entityId: json['entity_id'] as String?,
      reason: json['reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class EventReport {
  const EventReport({
    required this.summary,
    required this.staffing,
    required this.auditHistory,
  });

  final EventReportSummary summary;
  final List<StaffingReportRow> staffing;
  final List<EventAuditHistoryRow> auditHistory;
}

String buildEventReportText(EventReport report) {
  final summary = report.summary;
  final lines = <String>[
    summary.title,
    '${summary.eventType} at ${summary.venueName}',
    'Reporting: ${formatKolkataDateTime12h(summary.reportingAt)}',
    'Workers: ${summary.confirmedWorkerCount}/${summary.requiredWorkerCount}',
    'Attendance: present ${summary.attendancePresent}, late ${summary.attendanceLate}, absent ${summary.attendanceAbsent}, not marked ${summary.attendanceNotMarked}',
    'Pay display: ${summary.currencyCode} ${summary.totalWorkerPayDisplay.toStringAsFixed(0)} per worker',
    '',
    'Confirmed staffing',
  ];

  for (final row in report.staffing) {
    final workerNumber = row.workerNumber == null
        ? '-'
        : '#${row.workerNumber}';
    lines.add(
      '${row.categoryAtConfirmation.databaseValue} $workerNumber ${row.fullName} ${row.phoneE164} ${row.attendanceStatus.label}',
    );
  }

  return lines.join('\n');
}
