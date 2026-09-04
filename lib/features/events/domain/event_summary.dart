enum EventStatus {
  draft,
  published,
  upcoming,
  inProgress,
  completed,
  closed,
  cancelled;

  static EventStatus fromDatabase(String value) {
    switch (value) {
      case 'DRAFT':
        return EventStatus.draft;
      case 'PUBLISHED':
        return EventStatus.published;
      case 'UPCOMING':
        return EventStatus.upcoming;
      case 'IN_PROGRESS':
        return EventStatus.inProgress;
      case 'COMPLETED':
        return EventStatus.completed;
      case 'CLOSED':
        return EventStatus.closed;
      case 'CANCELLED':
        return EventStatus.cancelled;
      default:
        throw FormatException('Unknown event status "$value".');
    }
  }

  String get databaseValue {
    switch (this) {
      case EventStatus.draft:
        return 'DRAFT';
      case EventStatus.published:
        return 'PUBLISHED';
      case EventStatus.upcoming:
        return 'UPCOMING';
      case EventStatus.inProgress:
        return 'IN_PROGRESS';
      case EventStatus.completed:
        return 'COMPLETED';
      case EventStatus.closed:
        return 'CLOSED';
      case EventStatus.cancelled:
        return 'CANCELLED';
    }
  }
}

enum RecruitmentStatus {
  notOpen,
  open,
  full,
  closed;

  static RecruitmentStatus fromDatabase(String value) {
    switch (value) {
      case 'NOT_OPEN':
        return RecruitmentStatus.notOpen;
      case 'OPEN':
        return RecruitmentStatus.open;
      case 'FULL':
        return RecruitmentStatus.full;
      case 'CLOSED':
        return RecruitmentStatus.closed;
      default:
        throw FormatException('Unknown recruitment status "$value".');
    }
  }

  String get databaseValue {
    switch (this) {
      case RecruitmentStatus.notOpen:
        return 'NOT_OPEN';
      case RecruitmentStatus.open:
        return 'OPEN';
      case RecruitmentStatus.full:
        return 'FULL';
      case RecruitmentStatus.closed:
        return 'CLOSED';
    }
  }
}

enum TierStrategy {
  standard,
  urgent,
  emergency,
  custom;

  String get databaseValue => name.toUpperCase();

  static TierStrategy fromDatabase(String value) {
    switch (value) {
      case 'STANDARD':
        return TierStrategy.standard;
      case 'URGENT':
        return TierStrategy.urgent;
      case 'EMERGENCY':
        return TierStrategy.emergency;
      case 'CUSTOM':
        return TierStrategy.custom;
      default:
        throw FormatException('Unknown tier strategy "$value".');
    }
  }
}

class EventSummary {
  const EventSummary({
    required this.id,
    required this.title,
    required this.eventType,
    required this.venueName,
    required this.eventDate,
    required this.reportingAt,
    required this.requiredWorkerCount,
    required this.dailyWage,
    required this.currencyCode,
    required this.eventStatus,
    required this.recruitmentStatus,
    required this.tierStrategy,
    required this.version,
  });

  final String id;
  final String title;
  final String eventType;
  final String venueName;
  final DateTime eventDate;
  final DateTime reportingAt;
  final int requiredWorkerCount;
  final double dailyWage;
  final String currencyCode;
  final EventStatus eventStatus;
  final RecruitmentStatus recruitmentStatus;
  final TierStrategy tierStrategy;
  final int version;

  static EventSummary fromJson(Map<String, dynamic> json) {
    return EventSummary(
      id: json['id'] as String,
      title: json['title'] as String,
      eventType: json['event_type'] as String,
      venueName: json['venue_name'] as String,
      eventDate: DateTime.parse(json['event_date'] as String),
      reportingAt: DateTime.parse(json['reporting_at'] as String),
      requiredWorkerCount: (json['required_worker_count'] as num).toInt(),
      dailyWage: (json['daily_wage'] as num).toDouble(),
      currencyCode: json['currency_code'] as String,
      eventStatus: EventStatus.fromDatabase(json['event_status'] as String),
      recruitmentStatus: RecruitmentStatus.fromDatabase(
        json['recruitment_status'] as String,
      ),
      tierStrategy: TierStrategy.fromDatabase(json['tier_strategy'] as String),
      version: (json['version'] as num).toInt(),
    );
  }
}

class EventDraftInput {
  const EventDraftInput({
    required this.title,
    required this.eventType,
    required this.venueName,
    required this.reportingAt,
    required this.workStartsAt,
    required this.expectedEndsAt,
    required this.requiredWorkerCount,
    required this.dailyWage,
    required this.tierStrategy,
    this.mapsUrl,
    this.instructions,
    this.dressCode,
  });

  final String title;
  final String eventType;
  final String venueName;
  final String? mapsUrl;
  final DateTime reportingAt;
  final DateTime workStartsAt;
  final DateTime expectedEndsAt;
  final int requiredWorkerCount;
  final double dailyWage;
  final TierStrategy tierStrategy;
  final String? instructions;
  final String? dressCode;

  Map<String, dynamic> toCreateRpcParams() => {
    'p_title': title,
    'p_event_type': eventType,
    'p_venue_name': venueName,
    'p_maps_url': mapsUrl,
    'p_reporting_at': reportingAt.toIso8601String(),
    'p_work_starts_at': workStartsAt.toIso8601String(),
    'p_expected_ends_at': expectedEndsAt.toIso8601String(),
    'p_required_worker_count': requiredWorkerCount,
    'p_daily_wage': dailyWage,
    'p_tier_strategy': tierStrategy.databaseValue,
    'p_instructions': instructions,
    'p_dress_code': dressCode,
    'p_leaders': <Map<String, dynamic>>[],
    'p_requirements': <Map<String, dynamic>>[],
    'p_allowances': <Map<String, dynamic>>[],
  };
}

String formatKolkataDateTime12h(DateTime value) {
  final utc = value.toUtc();
  final kolkata = utc.add(const Duration(hours: 5, minutes: 30));
  final hour12 = kolkata.hour % 12 == 0 ? 12 : kolkata.hour % 12;
  final minute = kolkata.minute.toString().padLeft(2, '0');
  final suffix = kolkata.hour >= 12 ? 'PM' : 'AM';
  return '${kolkata.day.toString().padLeft(2, '0')}/'
      '${kolkata.month.toString().padLeft(2, '0')}/'
      '${kolkata.year} $hour12:$minute $suffix';
}
