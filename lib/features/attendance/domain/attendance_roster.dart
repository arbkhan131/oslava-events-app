import '../../booking/domain/worker_assignment.dart';
import '../../workers/domain/worker_profile.dart';

enum AttendanceStatus {
  notMarked,
  present,
  late,
  absent;

  static AttendanceStatus fromDatabase(String value) {
    switch (value) {
      case 'NOT_MARKED':
        return AttendanceStatus.notMarked;
      case 'PRESENT':
        return AttendanceStatus.present;
      case 'LATE':
        return AttendanceStatus.late;
      case 'ABSENT':
        return AttendanceStatus.absent;
      default:
        throw FormatException('Unknown attendance status "$value".');
    }
  }

  String get databaseValue {
    switch (this) {
      case AttendanceStatus.notMarked:
        return 'NOT_MARKED';
      case AttendanceStatus.present:
        return 'PRESENT';
      case AttendanceStatus.late:
        return 'LATE';
      case AttendanceStatus.absent:
        return 'ABSENT';
    }
  }

  String get label {
    switch (this) {
      case AttendanceStatus.notMarked:
        return 'Not marked';
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.late:
        return 'Late';
      case AttendanceStatus.absent:
        return 'Absent';
    }
  }
}

class AttendanceRosterEntry {
  const AttendanceRosterEntry({
    required this.assignmentId,
    required this.eventId,
    required this.workerId,
    required this.fullName,
    required this.phoneE164,
    required this.categoryAtConfirmation,
    required this.assignmentStatus,
    required this.attendanceStatus,
    this.workerNumber,
    this.profilePhotoPath,
    this.currentCategory,
    this.markedAt,
    this.notes,
    this.totalCount,
    this.filteredCount,
    this.fullCounters,
    this.reviewId,
    this.reviewStars,
    this.reviewTags = const [],
    this.reviewNotes,
    this.reviewUpdatedAt,
  });

  final String assignmentId;
  final String eventId;
  final String workerId;
  final int? workerNumber;
  final String fullName;
  final String phoneE164;
  final String? profilePhotoPath;
  final WorkerCategory categoryAtConfirmation;
  final WorkerCategory? currentCategory;
  final AssignmentStatus assignmentStatus;
  final AttendanceStatus attendanceStatus;
  final DateTime? markedAt;
  final String? notes;
  final int? totalCount;
  final int? filteredCount;
  final AttendanceCounters? fullCounters;
  final String? reviewId;
  final int? reviewStars;
  final List<String> reviewTags;
  final String? reviewNotes;
  final DateTime? reviewUpdatedAt;

  static AttendanceRosterEntry fromJson(Map<String, dynamic> json) {
    return AttendanceRosterEntry(
      assignmentId: json['assignment_id'] as String,
      eventId: json['event_id'] as String,
      workerId: json['worker_id'] as String,
      workerNumber: (json['worker_number'] as num?)?.toInt(),
      fullName: json['full_name'] as String,
      phoneE164: json['phone_e164'] as String,
      profilePhotoPath: json['profile_photo_path'] as String?,
      categoryAtConfirmation: WorkerCategory.fromDatabase(
        json['category_at_confirmation'] as String?,
      )!,
      currentCategory: WorkerCategory.fromDatabase(
        json['current_category'] as String?,
      ),
      assignmentStatus: AssignmentStatus.fromDatabase(
        json['assignment_status'] as String,
      ),
      attendanceStatus: AttendanceStatus.fromDatabase(
        json['attendance_status'] as String,
      ),
      markedAt: json['marked_at'] == null
          ? null
          : DateTime.parse(json['marked_at'] as String),
      notes: json['notes'] as String?,
      totalCount: (json['total_count'] as num?)?.toInt(),
      filteredCount: (json['filtered_count'] as num?)?.toInt(),
      fullCounters: json['total_count'] == null
          ? null
          : AttendanceCounters(
              total: (json['total_count'] as num).toInt(),
              filtered: (json['filtered_count'] as num?)?.toInt(),
              notMarked: (json['not_marked_count'] as num?)?.toInt() ?? 0,
              present: (json['present_count'] as num?)?.toInt() ?? 0,
              late: (json['late_count'] as num?)?.toInt() ?? 0,
              absent: (json['absent_count'] as num?)?.toInt() ?? 0,
            ),
      reviewId: json['review_id'] as String?,
      reviewStars: (json['review_stars'] as num?)?.toInt(),
      reviewTags: (json['review_tags'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      reviewNotes: json['review_notes'] as String?,
      reviewUpdatedAt: json['review_updated_at'] == null
          ? null
          : DateTime.parse(json['review_updated_at'] as String),
    );
  }
}

class AttendanceCounters {
  const AttendanceCounters({
    required this.total,
    required this.notMarked,
    required this.present,
    required this.late,
    required this.absent,
    this.filtered,
  });

  final int total;
  final int? filtered;
  final int notMarked;
  final int present;
  final int late;
  final int absent;

  static AttendanceCounters fromRoster(List<AttendanceRosterEntry> roster) {
    var notMarked = 0;
    var present = 0;
    var late = 0;
    var absent = 0;

    for (final row in roster) {
      switch (row.attendanceStatus) {
        case AttendanceStatus.notMarked:
          notMarked += 1;
        case AttendanceStatus.present:
          present += 1;
        case AttendanceStatus.late:
          late += 1;
        case AttendanceStatus.absent:
          absent += 1;
      }
    }

    return AttendanceCounters(
      total: roster.length,
      filtered: null,
      notMarked: notMarked,
      present: present,
      late: late,
      absent: absent,
    );
  }
}

class FieldEventDashboard {
  const FieldEventDashboard({
    required this.eventCount,
    required this.assignedTodayCount,
    required this.requiredTodayCount,
    required this.confirmedTodayCount,
    required this.attendanceTotal,
    required this.attendanceNotMarked,
    required this.attendancePresent,
    required this.attendanceLate,
    required this.attendanceAbsent,
  });

  final int eventCount;
  final int assignedTodayCount;
  final int requiredTodayCount;
  final int confirmedTodayCount;
  final int attendanceTotal;
  final int attendanceNotMarked;
  final int attendancePresent;
  final int attendanceLate;
  final int attendanceAbsent;

  static FieldEventDashboard fromJson(Map<String, dynamic> json) {
    return FieldEventDashboard(
      eventCount: (json['event_count'] as num).toInt(),
      assignedTodayCount: (json['assigned_today_count'] as num).toInt(),
      requiredTodayCount: (json['required_today_count'] as num).toInt(),
      confirmedTodayCount: (json['confirmed_today_count'] as num).toInt(),
      attendanceTotal: (json['attendance_total'] as num).toInt(),
      attendanceNotMarked: (json['attendance_not_marked'] as num).toInt(),
      attendancePresent: (json['attendance_present'] as num).toInt(),
      attendanceLate: (json['attendance_late'] as num).toInt(),
      attendanceAbsent: (json['attendance_absent'] as num).toInt(),
    );
  }
}
