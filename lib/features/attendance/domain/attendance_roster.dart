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
  });

  final int total;
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
      notMarked: notMarked,
      present: present,
      late: late,
      absent: absent,
    );
  }
}
