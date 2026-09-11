import 'booking_application_result.dart';

/// Bounded polling never converts an unresolved request into success or failure.
/// A later call resumes the same server request after a timeout or disconnection.
Future<BookingApplicationResult> settleBooking(
  BookingApplicationResult initial, {
  required Future<BookingApplicationResult> Function(String requestId) fetch,
  Future<void> Function(Duration)? delay,
  int maxPolls = 6,
}) async {
  var result = initial;
  final wait = delay ?? Future<void>.delayed;
  for (var attempt = 0; result.isPending && attempt < maxPolls; attempt++) {
    await wait(const Duration(milliseconds: 500));
    result = await fetch(initial.bookingRequestId);
  }
  return result;
}
