import '../../booking/domain/booking_application_result.dart';

class FriendWorker {
  const FriendWorker({
    required this.workerId,
    required this.fullName,
    required this.phoneE164,
    required this.category,
    required this.tierEligible,
    this.workerNumber,
  });

  final String workerId;
  final int? workerNumber;
  final String fullName;
  final String phoneE164;
  final String category;
  final bool? tierEligible;

  bool get canBookForEvent => tierEligible != false;

  static FriendWorker fromJson(Map<String, dynamic> json) {
    return FriendWorker(
      workerId: json['worker_id'] as String,
      workerNumber: (json['worker_number'] as num?)?.toInt(),
      fullName: json['full_name'] as String,
      phoneE164: json['phone_e164'] as String,
      category: json['category'] as String,
      tierEligible: json['tier_eligible'] as bool?,
    );
  }
}

class FriendBookingResult {
  const FriendBookingResult({
    required this.friendBookingRequestId,
    required this.status,
    required this.eventId,
    required this.requesterId,
    required this.friendId,
    required this.vacancyCount,
    this.detailCode,
    this.requesterBookingRequestId,
    this.friendBookingRequestIdInner,
    this.requesterAssignmentId,
    this.friendAssignmentId,
  });

  final String friendBookingRequestId;
  final BookingResultStatus status;
  final String? detailCode;
  final String eventId;
  final String requesterId;
  final String friendId;
  final String? requesterBookingRequestId;
  final String? friendBookingRequestIdInner;
  final String? requesterAssignmentId;
  final String? friendAssignmentId;
  final int vacancyCount;

  bool get isConfirmed => status == BookingResultStatus.confirmed;

  static FriendBookingResult fromJson(Map<String, dynamic> json) {
    return FriendBookingResult(
      friendBookingRequestId: json['friend_booking_request_id'] as String,
      status: BookingResultStatus.fromDatabase(json['result'] as String),
      detailCode: json['result_detail_code'] as String?,
      eventId: json['event_id'] as String,
      requesterId: json['requester_id'] as String,
      friendId: json['friend_id'] as String,
      requesterBookingRequestId:
          json['requester_booking_request_id'] as String?,
      friendBookingRequestIdInner:
          json['friend_booking_request_id_inner'] as String?,
      requesterAssignmentId: json['requester_assignment_id'] as String?,
      friendAssignmentId: json['friend_assignment_id'] as String?,
      vacancyCount: (json['vacancy_count'] as num).toInt(),
    );
  }
}

String friendBookingResultMessage(FriendBookingResult result) {
  if (result.isConfirmed) {
    return 'You and your friend are confirmed for this event.';
  }

  switch (result.detailCode) {
    case 'PAIR_REQUIRES_TWO_OPEN_VACANCIES':
      return 'Join with friend needs two open vacancies.';
    case 'ACTIVE_APPLICATION_EXISTS':
      return 'You or your friend already has a pending application for this event.';
    case 'FRIEND_ACTIVE_WORKER_REQUIRED':
      return 'That friend is not an approved active worker yet.';
    case 'FRIEND_TIER_NOT_OPEN':
      return 'Your friend’s category is not open for this event yet.';
    case 'FRIEND_ONE_HOUR_CONFLICT':
      return 'Your friend has confirmed work that conflicts with this event.';
    case 'FRIEND_PROFILE_INCOMPLETE':
      return 'Your friend must complete their profile before joining.';
    case 'FRIEND_ACTIVE_ASSIGNMENT_OR_WAITLIST_EXISTS':
      return 'Your friend already has an assignment or waitlist entry for this event.';
    case 'FRIEND_MISSING_ACKNOWLEDGEMENT':
      return 'Required acknowledgements are missing for your friend booking.';
  }

  final singleResult = BookingApplicationResult(
    bookingRequestId:
        result.requesterBookingRequestId ?? result.friendBookingRequestId,
    status: result.status,
    detailCode: result.detailCode,
    assignmentId: result.requesterAssignmentId,
    eventId: result.eventId,
    vacancyCount: result.vacancyCount,
  );
  return bookingResultMessage(singleResult);
}
