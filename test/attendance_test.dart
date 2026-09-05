import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/app/router/app_router.dart';
import 'package:oslava_events/features/attendance/domain/attendance_roster.dart';
import 'package:oslava_events/features/auth/application/auth_session.dart';
import 'package:oslava_events/features/booking/domain/worker_assignment.dart';
import 'package:oslava_events/features/workers/domain/worker_profile.dart';

void main() {
  group('Phase 11 attendance models', () {
    test('parses roster rows and attendance statuses', () {
      final entry = AttendanceRosterEntry.fromJson({
        'assignment_id': 'assignment-id',
        'event_id': 'event-id',
        'worker_id': 'worker-id',
        'worker_number': 100123,
        'full_name': 'Worker One',
        'phone_e164': '+919000000005',
        'profile_photo_path': 'worker-id/profile.jpg',
        'category_at_confirmation': 'A',
        'current_category': 'B',
        'assignment_status': 'CONFIRMED',
        'attendance_status': 'LATE',
        'marked_at': '2026-10-10T10:30:00Z',
        'notes': 'Traffic delay',
      });

      expect(entry.workerNumber, 100123);
      expect(entry.categoryAtConfirmation, WorkerCategory.a);
      expect(entry.currentCategory, WorkerCategory.b);
      expect(entry.assignmentStatus, AssignmentStatus.confirmed);
      expect(entry.attendanceStatus, AttendanceStatus.late);
      expect(entry.notes, 'Traffic delay');
    });

    test('computes counters from roster statuses', () {
      AttendanceRosterEntry row(AttendanceStatus status) {
        return AttendanceRosterEntry(
          assignmentId: 'assignment-${status.databaseValue}',
          eventId: 'event-id',
          workerId: 'worker-${status.databaseValue}',
          fullName: 'Worker',
          phoneE164: '+919000000005',
          categoryAtConfirmation: WorkerCategory.f,
          assignmentStatus: AssignmentStatus.confirmed,
          attendanceStatus: status,
        );
      }

      final counters = AttendanceCounters.fromRoster([
        row(AttendanceStatus.notMarked),
        row(AttendanceStatus.present),
        row(AttendanceStatus.late),
        row(AttendanceStatus.absent),
      ]);

      expect(counters.total, 4);
      expect(counters.notMarked, 1);
      expect(counters.present, 1);
      expect(counters.late, 1);
      expect(counters.absent, 1);
    });
  });

  group('Phase 11 route guards', () {
    test('Captain can open field event routes', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.captain,
          location: '/captain/events',
        ),
        isNull,
      );

      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.captain,
          location: '/captain/events/event-id',
        ),
        isNull,
      );
    });

    test('Worker cannot open field attendance routes', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.worker,
          location: '/captain/events/event-id',
        ),
        '/worker',
      );
    });

    test('Admin can open attendance from admin events', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.admin,
          location: '/admin/events/event-id/attendance',
        ),
        isNull,
      );
    });
  });
}
