enum WaitlistEntryStatus {
  waiting,
  promoted,
  withdrawn,
  skipped,
  expired;

  static WaitlistEntryStatus fromDatabase(String value) {
    switch (value) {
      case 'WAITING':
        return WaitlistEntryStatus.waiting;
      case 'PROMOTED':
        return WaitlistEntryStatus.promoted;
      case 'WITHDRAWN':
        return WaitlistEntryStatus.withdrawn;
      case 'SKIPPED':
        return WaitlistEntryStatus.skipped;
      case 'EXPIRED':
        return WaitlistEntryStatus.expired;
      default:
        throw FormatException('Unknown waitlist status "$value".');
    }
  }
}

class WaitlistResult {
  const WaitlistResult({
    required this.status,
    this.waitlistEntryId,
    this.detailCode,
    this.queuePosition,
  });

  final String? waitlistEntryId;
  final WaitlistEntryStatus? status;
  final String? detailCode;
  final int? queuePosition;

  static WaitlistResult fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'] as String?;
    return WaitlistResult(
      waitlistEntryId: json['waitlist_entry_id'] as String?,
      status: rawStatus == null
          ? null
          : WaitlistEntryStatus.fromDatabase(rawStatus),
      detailCode: json['result_detail_code'] as String?,
      queuePosition: (json['queue_position'] as num?)?.toInt(),
    );
  }
}

String waitlistResultMessage(WaitlistResult result) {
  if (result.status == WaitlistEntryStatus.waiting) {
    return result.queuePosition == null
        ? 'Waitlist joined.'
        : 'Waitlist joined. Position ${result.queuePosition}.';
  }

  return switch (result.detailCode) {
    'DUPLICATE' => 'You are already on this waitlist.',
    'EVENT_NOT_FULL' => 'Waitlist is available only when the event is full.',
    'TIER_NOT_OPEN' => 'Your category is not open for this event yet.',
    'ACTIVE_ASSIGNMENT_EXISTS' => 'You are already confirmed for this event.',
    'MISSING_ACKNOWLEDGEMENT' => 'Required acknowledgements are missing.',
    'ONE_HOUR_CONFLICT' => 'This event conflicts with confirmed work.',
    'ACTIVE_COMPLETE_WORKER_REQUIRED' =>
      'Complete your profile before joining the waitlist.',
    _ => 'Waitlist request could not be completed.',
  };
}
