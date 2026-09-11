import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/app/router/app_router.dart';
import 'package:oslava_events/features/attendance/domain/attendance_roster.dart';
import 'package:oslava_events/features/auth/application/auth_session.dart';
import 'package:oslava_events/features/booking/domain/worker_assignment.dart';
import 'package:oslava_events/features/performance/domain/performance_review.dart';
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

    test('parses enhanced roster counters and existing review values', () {
      final entry = AttendanceRosterEntry.fromJson({
        'assignment_id': 'assignment-id',
        'event_id': 'event-id',
        'worker_id': 'worker-id',
        'worker_number': 100123,
        'full_name': 'Worker One',
        'phone_e164': '+919000000005',
        'profile_photo_path': 'worker-id/profile.jpg',
        'category_at_confirmation': 'A',
        'current_category': 'A',
        'assignment_status': 'CONFIRMED',
        'attendance_status': 'PRESENT',
        'total_count': 10,
        'filtered_count': 2,
        'not_marked_count': 4,
        'present_count': 3,
        'late_count': 2,
        'absent_count': 1,
        'review_id': 'review-id',
        'review_stars': 4,
        'review_tags': ['punctual'],
        'review_notes': 'Strong shift',
        'review_updated_at': '2026-10-10T12:30:00Z',
      });

      expect(entry.fullCounters?.total, 10);
      expect(entry.fullCounters?.filtered, 2);
      expect(entry.fullCounters?.notMarked, 4);
      expect(entry.reviewStars, 4);
      expect(entry.reviewTags, ['punctual']);
      expect(entry.reviewUpdatedAt, DateTime.parse('2026-10-10T12:30:00Z'));
    });

    test('parses field dashboard counters', () {
      final dashboard = FieldEventDashboard.fromJson({
        'event_count': 5,
        'assigned_today_count': 2,
        'required_today_count': 20,
        'confirmed_today_count': 18,
        'attendance_total': 18,
        'attendance_not_marked': 3,
        'attendance_present': 12,
        'attendance_late': 2,
        'attendance_absent': 1,
      });

      expect(dashboard.assignedTodayCount, 2);
      expect(dashboard.requiredTodayCount, 20);
      expect(dashboard.attendanceNotMarked, 3);
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

  group('Phase 12 performance review models', () {
    test('builds record_performance_review RPC params', () {
      const input = PerformanceReviewInput(
        assignmentId: 'assignment-id',
        stars: 5,
        tags: ['punctual', 'professional'],
        notes: 'Strong shift',
      );

      expect(input.toRpcParams(), {
        'p_assignment_id': 'assignment-id',
        'p_stars': 5,
        'p_tags': ['punctual', 'professional'],
        'p_notes': 'Strong shift',
      });
    });

    test('parses performance review RPC result', () {
      final result = PerformanceReviewResult.fromJson({
        'review_id': 'review-id',
        'event_id': 'event-id',
        'assignment_id': 'assignment-id',
        'worker_id': 'worker-id',
        'reviewer_id': 'reviewer-id',
        'reviewer_role': 'CAPTAIN',
        'stars': 4,
        'tags': ['corrected'],
        'notes': 'Updated before close',
        'updated_at': '2026-10-12T10:30:00Z',
      });

      expect(result.stars, 4);
      expect(result.tags, ['corrected']);
      expect(result.notes, 'Updated before close');
      expect(result.updatedAt, DateTime.parse('2026-10-12T10:30:00Z'));
    });
  });
}
