import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/app/router/app_router.dart';
import 'package:oslava_events/features/auth/application/auth_session.dart';
import 'package:oslava_events/features/booking/domain/booking_application_result.dart';
import 'package:oslava_events/features/booking/domain/waitlist_result.dart';
import 'package:oslava_events/features/booking/domain/worker_assignment.dart';
import 'package:oslava_events/features/events/domain/event_summary.dart';
import 'package:oslava_events/features/events/domain/worker_event.dart';

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

    test('describes approved tier release preset offsets', () {
      expect(
        describeTierReleaseOffsets(
          TierReleaseOffsets.presetFor(TierStrategy.standard),
        ),
        'A 0m, B 30m, C 60m, F 180m',
      );
      expect(
        describeTierReleaseOffsets(
          TierReleaseOffsets.presetFor(TierStrategy.urgent),
        ),
        'A 0m, B 15m, C 30m, F 60m',
      );
      expect(
        describeTierReleaseOffsets(
          TierReleaseOffsets.presetFor(TierStrategy.emergency),
        ),
        'A 0m, B 5m, C 10m, F 15m',
      );
    });

    test('validates custom tier release ordering', () {
      expect(
        const TierReleaseOffsets(
          aMinutes: 10,
          bMinutes: 20,
          cMinutes: 30,
          fMinutes: 40,
        ).isValid,
        isTrue,
      );
      expect(
        const TierReleaseOffsets(
          aMinutes: 20,
          bMinutes: 10,
          cMinutes: 30,
          fMinutes: 40,
        ).isValid,
        isFalse,
      );
    });

    test('maps custom tier release offsets to configure RPC params', () {
      expect(
        const TierReleaseOffsets(
          aMinutes: 1,
          bMinutes: 2,
          cMinutes: 3,
          fMinutes: 4,
        ).toConfigureRpcParams('event-id'),
        containsPair('p_event_id', 'event-id'),
      );
      expect(
        const TierReleaseOffsets(
          aMinutes: 1,
          bMinutes: 2,
          cMinutes: 3,
          fMinutes: 4,
        ).toConfigureRpcParams('event-id'),
        containsPair('p_f_offset_minutes', 4),
      );
    });

    test('maps admin event create and update payloads with child rows', () {
      final input = EventDraftInput(
        title: 'Night Wedding',
        eventType: 'Wedding',
        venueName: 'Oslava Banquet',
        mapsUrl: 'https://maps.example/event',
        reportingAt: DateTime.utc(2026, 10, 10, 13, 30),
        workStartsAt: DateTime.utc(2026, 10, 10, 14, 30),
        expectedEndsAt: DateTime.utc(2026, 10, 10, 22, 30),
        requiredWorkerCount: 12,
        dailyWage: 1500,
        tierStrategy: TierStrategy.custom,
        instructions: 'Report at main gate',
        dressCode: 'Black shirt',
        leaders: const [
          EventLeaderInput(userId: 'captain-id', leaderRole: 'CAPTAIN'),
        ],
        requirements: const [
          EventRequirementInput(
            name: 'Carry ID',
            acknowledgementRequired: true,
            extraAllowanceAmount: 100,
          ),
        ],
        allowances: const [EventAllowanceInput(label: 'Travel', amount: 250)],
      );

      final create = input.toCreateRpcParams();
      expect(create['p_leaders'], [
        {'user_id': 'captain-id', 'leader_role': 'CAPTAIN'},
      ]);
      expect(
        (create['p_requirements'] as List).single,
        containsPair('acknowledgement_required', true),
      );
      expect(
        (create['p_allowances'] as List).single,
        containsPair('amount', 250),
      );

      final update = input.toUpdateRpcParams(
        eventId: 'event-id',
        expectedVersion: 7,
        reason: 'Schedule correction',
        confirmConflicts: true,
      );
      expect(update, containsPair('p_event_id', 'event-id'));
      expect(update, containsPair('p_expected_version', 7));
      expect(update, containsPair('p_confirm_conflicts', true));
      expect(update, containsPair('p_reason', 'Schedule correction'));
    });

    test('parses admin event detail and dashboard readiness counters', () {
      final detail = AdminEventDetail.fromJson({
        'id': 'event-id',
        'title': 'Festival Staffing',
        'event_type': 'Festival',
        'venue_name': 'Oslava Grounds',
        'maps_url': 'https://maps.example/event',
        'event_date': '2026-10-10',
        'reporting_at': '2026-10-10T09:30:00Z',
        'work_starts_at': '2026-10-10T10:30:00Z',
        'expected_ends_at': '2026-10-10T18:30:00Z',
        'required_worker_count': 25,
        'daily_wage': 1200,
        'currency_code': 'INR',
        'event_status': 'PUBLISHED',
        'recruitment_status': 'OPEN',
        'tier_strategy': 'STANDARD',
        'version': 3,
        'instructions': 'Report at main gate',
        'dress_code': 'Black shirt',
        'confirmed_count': 10,
        'waitlist_count': 2,
        'open_review_flags': 1,
        'leaders': [
          {
            'user_id': 'captain-id',
            'full_name': 'Captain One',
            'leader_role': 'CAPTAIN',
          },
        ],
        'requirements': [
          {
            'name': 'Carry ID',
            'description': 'Government ID',
            'is_mandatory': true,
            'acknowledgement_required': true,
            'extra_allowance_amount': 100,
            'display_order': 0,
          },
        ],
        'allowances': [
          {
            'label': 'Travel',
            'description': 'Taxi',
            'amount': 250,
            'display_order': 0,
          },
        ],
      });

      expect(detail.confirmedCount, 10);
      expect(detail.waitlistCount, 2);
      expect(detail.openReviewFlags, 1);
      expect(detail.leaders.single.fullName, 'Captain One');
      expect(detail.requirements.single.acknowledgementRequired, isTrue);
      expect(detail.allowances.single.amount, 250);
      expect(detail.toDraftInput().leaders.single.userId, 'captain-id');

      final dashboard = AdminEventDashboard.fromJson({
        'today_event_count': 2,
        'draft_count': 1,
        'published_count': 3,
        'upcoming_count': 4,
        'in_progress_count': 5,
        'completed_count': 6,
        'open_review_flag_count': 7,
        'required_today_count': 20,
        'confirmed_today_count': 16,
        'vacant_today_count': 4,
      });

      expect(dashboard.requiredTodayCount, 20);
      expect(dashboard.confirmedTodayCount, 16);
      expect(dashboard.vacantTodayCount, 4);
      expect(dashboard.openReviewFlagCount, 7);
    });

    test('tier countdown never returns a negative duration', () {
      final now = DateTime.utc(2026, 10, 10, 9);

      expect(
        timeUntilTierOpens(
          opensAt: now.add(const Duration(minutes: 15)),
          now: now,
        ),
        const Duration(minutes: 15),
      );
      expect(
        timeUntilTierOpens(
          opensAt: now.subtract(const Duration(minutes: 15)),
          now: now,
        ),
        Duration.zero,
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

  group('Phase 7 worker event discovery', () {
    test('parses worker event board rows with server action state', () {
      final event = WorkerEvent.fromJson({
        'id': 'event-id',
        'title': 'Festival Staffing',
        'event_type': 'Festival',
        'venue_name': 'Oslava Grounds',
        'maps_url': 'https://maps.example/event',
        'event_date': '2026-10-10',
        'reporting_at': '2026-10-10T09:30:00Z',
        'work_starts_at': '2026-10-10T10:30:00Z',
        'expected_ends_at': '2026-10-10T18:30:00Z',
        'required_worker_count': 25,
        'active_confirmed_count': 10,
        'vacancy_count': 15,
        'daily_wage': 1200,
        'currency_code': 'INR',
        'event_status': 'PUBLISHED',
        'recruitment_status': 'OPEN',
        'tier_strategy': 'STANDARD',
        'worker_category': 'A',
        'own_tier_opens_at': '2026-10-10T09:30:00Z',
        'open_categories': ['A', 'B'],
        'action_state': 'AVAILABLE',
        'action_label': 'Apply',
        'instructions': 'Bring ID',
        'dress_code': 'Black shirt',
      });

      expect(event.actionState, WorkerEventActionState.available);
      expect(event.openCategories, ['A', 'B']);
      expect(event.vacancyCount, 15);
      expect(event.canApply, isTrue);
      expect(event.canJoinWaitlist, isFalse);
    });

    test('full worker event exposes explicit waitlist action state', () {
      final event = WorkerEvent.fromJson({
        'id': 'event-id',
        'title': 'Full Event',
        'event_type': 'Concert',
        'venue_name': 'Oslava Grounds',
        'event_date': '2026-10-10',
        'reporting_at': '2026-10-10T09:30:00Z',
        'work_starts_at': '2026-10-10T10:30:00Z',
        'expected_ends_at': '2026-10-10T18:30:00Z',
        'required_worker_count': 25,
        'active_confirmed_count': 25,
        'vacancy_count': 0,
        'daily_wage': 1200,
        'currency_code': 'INR',
        'event_status': 'PUBLISHED',
        'recruitment_status': 'FULL',
        'tier_strategy': 'STANDARD',
        'open_categories': ['A', 'B', 'C', 'F'],
        'action_state': 'FULL',
        'action_label': 'Join Waitlist',
      });

      expect(event.actionState, WorkerEventActionState.full);
      expect(event.actionLabel, 'Join Waitlist');
      expect(event.canJoinWaitlist, isTrue);
    });

    test('parses worker event detail requirements allowances leaders and waitlist state', () {
      final event = WorkerEvent.fromJson({
        'id': 'event-id',
        'title': 'Detailed Worker Event',
        'event_type': 'Wedding',
        'venue_name': 'Oslava Hall',
        'maps_url': 'https://maps.example/event',
        'event_date': '2026-10-10',
        'reporting_at': '2026-10-10T09:30:00Z',
        'work_starts_at': '2026-10-10T10:30:00Z',
        'expected_ends_at': '2026-10-10T18:30:00Z',
        'required_worker_count': 10,
        'active_confirmed_count': 10,
        'vacancy_count': 0,
        'daily_wage': 1200,
        'currency_code': 'INR',
        'event_status': 'PUBLISHED',
        'recruitment_status': 'FULL',
        'tier_strategy': 'STANDARD',
        'worker_category': 'A',
        'own_tier_opens_at': '2026-10-10T08:30:00Z',
        'open_categories': ['A', 'B'],
        'action_state': 'WAITLISTED',
        'action_label': 'Waitlisted',
        'instructions': 'Report at gate 2',
        'dress_code': 'Black shirt',
        'own_waitlist_entry_id': 'waitlist-id',
        'own_waitlist_position': 3,
        'requirements': [
          {
            'id': 'requirement-id',
            'name': 'Carry ID',
            'description': 'Government ID',
            'is_mandatory': true,
            'acknowledgement_required': true,
            'extra_allowance_amount': 50,
            'currency_code': 'INR',
          },
        ],
        'allowances': [
          {
            'label': 'Travel',
            'description': 'Taxi',
            'amount': 200,
            'currency_code': 'INR',
          },
        ],
        'leaders': [
          {
            'user_id': 'captain-id',
            'full_name': 'Captain One',
            'leader_role': 'CAPTAIN',
          },
        ],
      });

      expect(event.ownWaitlistEntryId, 'waitlist-id');
      expect(event.ownWaitlistPosition, 3);
      expect(event.requirements.single.acknowledgementRequired, isTrue);
      expect(event.allowances.single.amount, 200);
      expect(event.leaders.single.fullName, 'Captain One');
    });

    test('parses worker waitlist entries for My Work', () {
      final entry = WorkerWaitlistEntry.fromJson({
        'waitlist_entry_id': 'waitlist-id',
        'event_id': 'event-id',
        'title': 'Full Event',
        'venue_name': 'Oslava Grounds',
        'reporting_at': '2026-10-10T09:30:00Z',
        'expected_ends_at': '2026-10-10T18:30:00Z',
        'status': 'WAITING',
        'queue_position': 2,
        'can_withdraw': true,
      });

      expect(entry.status, WaitlistEntryStatus.waiting);
      expect(entry.queuePosition, 2);
      expect(entry.canWithdraw, isTrue);
      expect(entry.reportingLabel, '10/10/2026 3:00 PM');
    });

    test('waitlisted worker event parses server state', () {
      final event = WorkerEvent.fromJson({
        'id': 'event-id',
        'title': 'Waitlisted Event',
        'event_type': 'Concert',
        'venue_name': 'Oslava Grounds',
        'event_date': '2026-10-10',
        'reporting_at': '2026-10-10T09:30:00Z',
        'work_starts_at': '2026-10-10T10:30:00Z',
        'expected_ends_at': '2026-10-10T18:30:00Z',
        'required_worker_count': 25,
        'active_confirmed_count': 25,
        'vacancy_count': 0,
        'daily_wage': 1200,
        'currency_code': 'INR',
        'event_status': 'PUBLISHED',
        'recruitment_status': 'FULL',
        'tier_strategy': 'STANDARD',
        'open_categories': ['A', 'B', 'C', 'F'],
        'action_state': 'WAITLISTED',
        'action_label': 'Waitlisted',
      });

      expect(event.actionState, WorkerEventActionState.waitlisted);
      expect(event.canJoinWaitlist, isFalse);
    });

    test('Worker can open event board, detail, and My Work routes', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.worker,
          location: '/worker/events',
        ),
        isNull,
      );
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.worker,
          location: '/worker/events/event-id',
        ),
        isNull,
      );
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.worker,
          location: '/worker/work',
        ),
        isNull,
      );
    });
  });

  group('Phase 9 booking results', () {
    test('parses confirmed apply result', () {
      final result = BookingApplicationResult.fromJson({
        'booking_request_id': 'request-id',
        'result': 'CONFIRMED',
        'result_detail_code': null,
        'assignment_id': 'assignment-id',
        'event_id': 'event-id',
        'vacancy_count': 0,
      });

      expect(result.status, BookingResultStatus.confirmed);
      expect(result.isConfirmed, isTrue);
      expect(bookingResultMessage(result), 'Application confirmed.');
    });

    test('maps server rejection details to worker messages', () {
      final incomplete = BookingApplicationResult.fromJson({
        'booking_request_id': 'request-id',
        'result': 'RESTRICTED',
        'result_detail_code': 'PROFILE_INCOMPLETE',
        'assignment_id': null,
        'event_id': 'event-id',
        'vacancy_count': 3,
      });

      expect(
        bookingResultMessage(incomplete),
        'Complete your profile before applying.',
      );

      final full = BookingApplicationResult.fromJson({
        'booking_request_id': 'request-id',
        'result': 'WAITLIST_AVAILABLE',
        'result_detail_code': 'FULL',
        'assignment_id': null,
        'event_id': 'event-id',
        'vacancy_count': 0,
      });

      expect(
        bookingResultMessage(full),
        'Event is full. Join Waitlist is available.',
      );
    });
  });

  group('Phase 10 cancellation and waitlist models', () {
    test('parses waitlist join result and message', () {
      final result = WaitlistResult.fromJson({
        'waitlist_entry_id': 'waitlist-id',
        'status': 'WAITING',
        'result_detail_code': null,
        'queue_position': 2,
      });

      expect(result.status, WaitlistEntryStatus.waiting);
      expect(waitlistResultMessage(result), 'Waitlist joined. Position 2.');
    });

    test('parses worker assignment cancellation state', () {
      final assignment = WorkerAssignment.fromJson({
        'assignment_id': 'assignment-id',
        'event_id': 'event-id',
        'title': 'Confirmed Event',
        'venue_name': 'Oslava Grounds',
        'reporting_at': '2026-10-10T09:30:00Z',
        'expected_ends_at': '2026-10-10T18:30:00Z',
        'assignment_status': 'CONFIRMED',
        'cancellation_deadline_at': '2026-10-10T08:30:00Z',
        'can_cancel': true,
      });

      expect(assignment.status, AssignmentStatus.confirmed);
      expect(assignment.canCancel, isTrue);
      expect(assignment.reportingLabel, '10/10/2026 3:00 PM');
    });

    test('parses cancellation result', () {
      final result = CancellationResult.fromJson({
        'cancellation_id': 'cancel-id',
        'assignment_id': 'assignment-id',
        'event_id': 'event-id',
        'status': 'CANCELLED',
        'promoted_assignment_id': 'promoted-id',
        'recruitment_status': 'FULL',
      });

      expect(result.status, AssignmentStatus.cancelled);
      expect(result.promotedAssignmentId, 'promoted-id');
      expect(result.recruitmentStatus, RecruitmentStatus.full);
    });
  });
}
