import 'event_summary.dart';

enum WorkerEventActionState {
  available,
  locked,
  full,
  confirmed,
  completed,
  cancelled,
  closed;

  static WorkerEventActionState fromDatabase(String value) {
    switch (value) {
      case 'AVAILABLE':
        return WorkerEventActionState.available;
      case 'LOCKED':
        return WorkerEventActionState.locked;
      case 'FULL':
        return WorkerEventActionState.full;
      case 'CONFIRMED':
        return WorkerEventActionState.confirmed;
      case 'COMPLETED':
        return WorkerEventActionState.completed;
      case 'CANCELLED':
        return WorkerEventActionState.cancelled;
      case 'CLOSED':
        return WorkerEventActionState.closed;
      default:
        throw FormatException('Unknown worker event action "$value".');
    }
  }
}

class WorkerEvent {
  const WorkerEvent({
    required this.id,
    required this.title,
    required this.eventType,
    required this.venueName,
    required this.eventDate,
    required this.reportingAt,
    required this.workStartsAt,
    required this.expectedEndsAt,
    required this.requiredWorkerCount,
    required this.activeConfirmedCount,
    required this.vacancyCount,
    required this.dailyWage,
    required this.currencyCode,
    required this.eventStatus,
    required this.recruitmentStatus,
    required this.tierStrategy,
    required this.openCategories,
    required this.actionState,
    required this.actionLabel,
    this.mapsUrl,
    this.workerCategory,
    this.ownTierOpensAt,
    this.instructions,
    this.dressCode,
  });

  final String id;
  final String title;
  final String eventType;
  final String venueName;
  final String? mapsUrl;
  final DateTime eventDate;
  final DateTime reportingAt;
  final DateTime workStartsAt;
  final DateTime expectedEndsAt;
  final int requiredWorkerCount;
  final int activeConfirmedCount;
  final int vacancyCount;
  final double dailyWage;
  final String currencyCode;
  final EventStatus eventStatus;
  final RecruitmentStatus recruitmentStatus;
  final TierStrategy tierStrategy;
  final String? workerCategory;
  final DateTime? ownTierOpensAt;
  final List<String> openCategories;
  final WorkerEventActionState actionState;
  final String actionLabel;
  final String? instructions;
  final String? dressCode;

  bool get canApply => actionState == WorkerEventActionState.available;
  bool get canJoinWaitlist => actionState == WorkerEventActionState.full;

  static WorkerEvent fromJson(Map<String, dynamic> json) {
    return WorkerEvent(
      id: json['id'] as String,
      title: json['title'] as String,
      eventType: json['event_type'] as String,
      venueName: json['venue_name'] as String,
      mapsUrl: json['maps_url'] as String?,
      eventDate: DateTime.parse(json['event_date'] as String),
      reportingAt: DateTime.parse(json['reporting_at'] as String),
      workStartsAt: DateTime.parse(json['work_starts_at'] as String),
      expectedEndsAt: DateTime.parse(json['expected_ends_at'] as String),
      requiredWorkerCount: (json['required_worker_count'] as num).toInt(),
      activeConfirmedCount: (json['active_confirmed_count'] as num).toInt(),
      vacancyCount: (json['vacancy_count'] as num).toInt(),
      dailyWage: (json['daily_wage'] as num).toDouble(),
      currencyCode: json['currency_code'] as String,
      eventStatus: EventStatus.fromDatabase(json['event_status'] as String),
      recruitmentStatus: RecruitmentStatus.fromDatabase(
        json['recruitment_status'] as String,
      ),
      tierStrategy: TierStrategy.fromDatabase(json['tier_strategy'] as String),
      workerCategory: json['worker_category'] as String?,
      ownTierOpensAt: json['own_tier_opens_at'] == null
          ? null
          : DateTime.parse(json['own_tier_opens_at'] as String),
      openCategories: (json['open_categories'] as List<dynamic>? ?? const [])
          .map((value) => value as String)
          .toList(),
      actionState: WorkerEventActionState.fromDatabase(
        json['action_state'] as String,
      ),
      actionLabel: json['action_label'] as String,
      instructions: json['instructions'] as String?,
      dressCode: json['dress_code'] as String?,
    );
  }
}
