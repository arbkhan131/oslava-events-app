import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/features/booking/domain/booking_application_result.dart';
import 'package:oslava_events/features/booking/domain/settle_booking.dart';

BookingApplicationResult result(BookingResultStatus status) =>
    BookingApplicationResult(
      bookingRequestId: 'request',
      status: status,
      eventId: 'event',
      vacancyCount: 1,
      assignmentId: status == BookingResultStatus.confirmed
          ? 'assignment'
          : null,
    );

void main() {
  test('pending never presents a confirmation', () {
    final pending = result(BookingResultStatus.pending);
    expect(pending.isConfirmed, false);
    expect(bookingResultMessage(pending), contains('not confirmed yet'));
  });
  test(
    'polls the same request until its authoritative result arrives',
    () async {
      var calls = 0;
      final settled = await settleBooking(
        result(BookingResultStatus.pending),
        delay: (_) async {},
        fetch: (id) async {
          expect(id, 'request');
          return result(
            ++calls == 2
                ? BookingResultStatus.confirmed
                : BookingResultStatus.pending,
          );
        },
      );
      expect(calls, 2);
      expect(settled.assignmentId, 'assignment');
    },
  );
  test('bounded polling leaves unresolved request pending', () async {
    var calls = 0;
    final settled = await settleBooking(
      result(BookingResultStatus.pending),
      delay: (_) async {},
      fetch: (_) async {
        calls++;
        return result(BookingResultStatus.pending);
      },
    );
    expect(calls, 6);
    expect(settled.isPending, true);
  });
  test('network failure does not fabricate a booking outcome', () async {
    await expectLater(
      settleBooking(
        result(BookingResultStatus.pending),
        delay: (_) async {},
        fetch: (_) async => throw StateError('offline'),
      ),
      throwsStateError,
    );
  });
  test('final rejection never polls or becomes confirmation', () async {
    final settled = await settleBooking(
      result(BookingResultStatus.waitlistAvailable),
      fetch: (_) async => throw StateError('must not poll'),
    );
    expect(settled.status, BookingResultStatus.waitlistAvailable);
  });
}
