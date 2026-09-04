import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/app/router/app_router.dart';
import 'package:oslava_events/features/auth/application/auth_session.dart';
import 'package:oslava_events/features/events/domain/event_summary.dart';

void main() {
  group('EventSummary', () {
    test('parses admin event rows with split statuses', () {
      final event = EventSummary.fromJson({
        'id': 'event-id',
        'title': 'Festival Staffing',
        'event_type': 'Festival',
        'venue_name': 'Oslava Grounds',
        'event_date': '2026-10-10',
        'reporting_at': '2026-10-10T09:30:00Z',
        'required_worker_count': 25,
        'daily_wage': 1200,
        'currency_code': 'INR',
        'event_status': 'PUBLISHED',
        'recruitment_status': 'NOT_OPEN',
        'tier_strategy': 'STANDARD',
        'version': 2,
      });

      expect(event.eventStatus, EventStatus.published);
      expect(event.recruitmentStatus, RecruitmentStatus.notOpen);
      expect(event.currencyCode, 'INR');
      expect(event.requiredWorkerCount, 25);
    });

    test('formats display time in 12-hour Asia/Kolkata time', () {
      expect(
        formatKolkataDateTime12h(DateTime.parse('2026-10-10T09:30:00Z')),
        '10/10/2026 3:00 PM',
      );
    });
  });

  group('Phase 5 event route guard', () {
    test('Worker cannot open admin events', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.worker,
          location: '/admin/events',
        ),
        '/worker',
      );
    });

    test('Admin can open admin events', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.admin,
          location: '/admin/events',
        ),
        isNull,
      );
    });

    test('Super Admin can open super-admin events', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.superAdmin,
          location: '/super-admin/events',
        ),
        isNull,
      );
    });
  });
}
