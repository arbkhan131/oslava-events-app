import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/app/router/app_router.dart';
import 'package:oslava_events/features/attendance/domain/attendance_roster.dart';
import 'package:oslava_events/features/auth/application/auth_session.dart';
import 'package:oslava_events/features/booking/domain/worker_assignment.dart';
import 'package:oslava_events/features/events/domain/event_summary.dart';
import 'package:oslava_events/features/reports/data/event_report_pdf.dart';
import 'package:oslava_events/features/reports/domain/event_report.dart';
import 'package:oslava_events/features/workers/domain/worker_profile.dart';

void main() {
  group('Phase 15 reports', () {
    test('parses event report summary and staffing rows', () {
      final summary = EventReportSummary.fromJson({
        'event_id': 'event-1',
        'title': 'Wedding staffing',
        'event_type': 'Wedding',
        'venue_name': 'Pune Hall',
        'event_date': '2026-09-07',
        'reporting_at': '2026-09-07T03:30:00.000Z',
        'work_starts_at': '2026-09-07T04:30:00.000Z',
        'expected_ends_at': '2026-09-07T12:30:00.000Z',
        'required_worker_count': 2,
        'confirmed_worker_count': 2,
        'daily_wage': 1200,
        'allowance_total': 150,
        'total_worker_pay_display': 1350,
        'currency_code': 'INR',
        'event_status': 'UPCOMING',
        'recruitment_status': 'FULL',
        'attendance_total': 2,
        'attendance_not_marked': 1,
        'attendance_present': 1,
        'attendance_late': 0,
        'attendance_absent': 0,
      });

      final row = StaffingReportRow.fromJson({
        'assignment_id': 'assignment-1',
        'worker_id': 'worker-1',
        'worker_number': 100001,
        'full_name': 'A Worker',
        'phone_e164': '+919000000008',
        'category_at_confirmation': 'A',
        'assignment_status': 'CONFIRMED',
        'confirmed_at': '2026-09-06T03:30:00.000Z',
        'attendance_status': 'PRESENT',
        'attendance_marked_at': '2026-09-07T03:35:00.000Z',
        'attendance_notes': 'Checked in',
        'daily_wage': 1200,
        'allowance_total': 150,
        'total_pay_display': 1350,
        'currency_code': 'INR',
      });

      expect(summary.totalWorkerPayDisplay, 1350);
      expect(summary.currencyCode, 'INR');
      expect(summary.attendancePresent, 1);
      expect(row.categoryAtConfirmation, WorkerCategory.a);
      expect(row.attendanceStatus, AttendanceStatus.present);
    });

    test('builds a shareable staffing summary snapshot', () {
      final report = _fixtureReport();

      final text = buildEventReportText(report);

      expect(text, contains('Wedding staffing'));
      expect(text, contains('Workers: 2/2'));
      expect(text, contains('Pay display: INR 1350 per worker'));
      expect(text, contains('A #100001 A Worker +919000000008 Present'));
    });

    test('builds PDF export bytes', () async {
      final bytes = await buildEventReportPdf(_fixtureReport());

      expect(bytes.length, greaterThan(500));
      expect(latin1.decode(bytes.take(4).toList()), '%PDF');
    });

    test('route guards protect report routes by active role namespace', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.worker,
          location: '/admin/events/event-1/report',
        ),
        '/worker',
      );
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.admin,
          location: '/admin/events/event-1/report',
        ),
        isNull,
      );
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.captain,
          location: '/captain/events/event-1/report',
        ),
        isNull,
      );
    });
  });
}

EventReport _fixtureReport() {
  return EventReport(
    summary: EventReportSummary(
      eventId: 'event-1',
      title: 'Wedding staffing',
      eventType: 'Wedding',
      venueName: 'Pune Hall',
      eventDate: DateTime.parse('2026-09-07'),
      reportingAt: DateTime.parse('2026-09-07T03:30:00.000Z'),
      workStartsAt: DateTime.parse('2026-09-07T04:30:00.000Z'),
      expectedEndsAt: DateTime.parse('2026-09-07T12:30:00.000Z'),
      requiredWorkerCount: 2,
      confirmedWorkerCount: 2,
      dailyWage: 1200,
      allowanceTotal: 150,
      totalWorkerPayDisplay: 1350,
      currencyCode: 'INR',
      eventStatus: EventStatus.upcoming,
      recruitmentStatus: RecruitmentStatus.full,
      attendanceTotal: 2,
      attendanceNotMarked: 1,
      attendancePresent: 1,
      attendanceLate: 0,
      attendanceAbsent: 0,
    ),
    staffing: [
      StaffingReportRow(
        assignmentId: 'assignment-1',
        workerId: 'worker-1',
        workerNumber: 100001,
        fullName: 'A Worker',
        phoneE164: '+919000000008',
        categoryAtConfirmation: WorkerCategory.a,
        assignmentStatus: AssignmentStatus.confirmed,
        confirmedAt: DateTime.parse('2026-09-06T03:30:00.000Z'),
        attendanceStatus: AttendanceStatus.present,
        dailyWage: 1200,
        allowanceTotal: 150,
        totalPayDisplay: 1350,
        currencyCode: 'INR',
      ),
    ],
    auditHistory: [
      EventAuditHistoryRow(
        historySource: 'event_history',
        action: 'EVENT_UPDATED',
        actorRole: 'ADMIN',
        entityType: 'event',
        createdAt: DateTime.parse('2026-09-06T03:30:00.000Z'),
      ),
    ],
  );
}
