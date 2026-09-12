import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/features/booking/domain/booking_application_result.dart';
import 'package:oslava_events/features/booking/domain/friend_booking.dart';

void main() {
  group('Friend booking models', () {
    test('parses friend worker search rows', () {
      final worker = FriendWorker.fromJson({
        'worker_id': 'worker-id',
        'worker_number': 42,
        'full_name': 'Muhammed Siyas K C',
        'phone_e164': '+918864938636',
        'category': 'C',
        'tier_eligible': true,
      });

      expect(worker.workerId, 'worker-id');
      expect(worker.workerNumber, 42);
      expect(worker.category, 'C');
      expect(worker.canBookForEvent, isTrue);
    });

    test('maps confirmed pair result to a friendly message', () {
      final result = FriendBookingResult.fromJson({
        'friend_booking_request_id': 'pair-id',
        'result': 'CONFIRMED',
        'result_detail_code': null,
        'event_id': 'event-id',
        'requester_id': 'requester-id',
        'friend_id': 'friend-id',
        'requester_booking_request_id': 'requester-booking-id',
        'friend_booking_request_id_inner': 'friend-booking-id',
        'requester_assignment_id': 'requester-assignment-id',
        'friend_assignment_id': 'friend-assignment-id',
        'vacancy_count': 0,
      });

      expect(result.status, BookingResultStatus.confirmed);
      expect(result.isConfirmed, isTrue);
      expect(
        friendBookingResultMessage(result),
        'You and your friend are confirmed for this event.',
      );
    });

    test('explains one-seat pair rejection', () {
      final result = FriendBookingResult.fromJson({
        'friend_booking_request_id': 'pair-id',
        'result': 'WAITLIST_AVAILABLE',
        'result_detail_code': 'PAIR_REQUIRES_TWO_OPEN_VACANCIES',
        'event_id': 'event-id',
        'requester_id': 'requester-id',
        'friend_id': 'friend-id',
        'requester_booking_request_id': 'requester-booking-id',
        'friend_booking_request_id_inner': 'friend-booking-id',
        'requester_assignment_id': null,
        'friend_assignment_id': null,
        'vacancy_count': 1,
      });

      expect(
        friendBookingResultMessage(result),
        'Join with friend needs two open vacancies.',
      );
    });
  });
}
