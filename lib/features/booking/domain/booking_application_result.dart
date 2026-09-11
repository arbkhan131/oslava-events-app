enum BookingResultStatus {
  pending,
  confirmed,
  full,
  waitlistAvailable,
  waitlisted,
  locked,
  conflict,
  restricted,
  duplicate,
  invalidRequirements,
  eventUnavailable,
  error;

  static BookingResultStatus fromDatabase(String value) {
    switch (value) {
      case 'PENDING':
        return BookingResultStatus.pending;
      case 'CONFIRMED':
        return BookingResultStatus.confirmed;
      case 'FULL':
        return BookingResultStatus.full;
      case 'WAITLIST_AVAILABLE':
        return BookingResultStatus.waitlistAvailable;
      case 'WAITLISTED':
        return BookingResultStatus.waitlisted;
      case 'LOCKED':
        return BookingResultStatus.locked;
      case 'CONFLICT':
        return BookingResultStatus.conflict;
      case 'RESTRICTED':
        return BookingResultStatus.restricted;
      case 'DUPLICATE':
        return BookingResultStatus.duplicate;
      case 'INVALID_REQUIREMENTS':
        return BookingResultStatus.invalidRequirements;
      case 'EVENT_UNAVAILABLE':
        return BookingResultStatus.eventUnavailable;
      case 'ERROR':
        return BookingResultStatus.error;
      default:
        throw FormatException('Unknown booking result "$value".');
    }
  }
}

class BookingApplicationResult {
  const BookingApplicationResult({
    required this.bookingRequestId,
    required this.status,
    required this.eventId,
    required this.vacancyCount,
    this.detailCode,
    this.assignmentId,
  });

  final String bookingRequestId;
  final BookingResultStatus status;
  final String eventId;
  final int vacancyCount;
  final String? detailCode;
  final String? assignmentId;

  bool get isConfirmed => status == BookingResultStatus.confirmed;
  bool get isPending => status == BookingResultStatus.pending;

  static BookingApplicationResult fromJson(Map<String, dynamic> json) {
    return BookingApplicationResult(
      bookingRequestId: json['booking_request_id'] as String,
      status: BookingResultStatus.fromDatabase(json['result'] as String),
      detailCode: json['result_detail_code'] as String?,
      assignmentId: json['assignment_id'] as String?,
      eventId: json['event_id'] as String,
      vacancyCount: (json['vacancy_count'] as num).toInt(),
    );
  }
}

String bookingResultMessage(BookingApplicationResult result) {
  switch (result.status) {
    case BookingResultStatus.confirmed:
      return 'Application confirmed.';
    case BookingResultStatus.waitlistAvailable:
      return 'Event is full. Join Waitlist is available.';
    case BookingResultStatus.locked:
      return 'Your category is not open for this event yet.';
    case BookingResultStatus.conflict:
      return 'This event conflicts with confirmed work.';
    case BookingResultStatus.restricted:
      return result.detailCode == 'PROFILE_INCOMPLETE'
          ? 'Complete your profile before applying.'
          : 'Your account cannot apply right now.';
    case BookingResultStatus.duplicate:
      return 'You already have an active application or assignment.';
    case BookingResultStatus.invalidRequirements:
      return 'Required acknowledgements are missing.';
    case BookingResultStatus.eventUnavailable:
      return 'This event is not available for applications.';
    case BookingResultStatus.error:
      return result.detailCode == 'LATE_CANCELLATION_ACK_REQUIRED'
          ? 'Late booking acknowledgement is required.'
          : 'Application could not be completed.';
    case BookingResultStatus.pending:
      return 'Application received. Checking the final seat. You are not confirmed yet.';
    case BookingResultStatus.full:
    case BookingResultStatus.waitlisted:
      return result.status.name;
  }
}
