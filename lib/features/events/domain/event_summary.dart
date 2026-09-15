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

class TierReleaseOffsets {
  const TierReleaseOffsets({
    required this.aMinutes,
    required this.bMinutes,
    required this.cMinutes,
    required this.fMinutes,
  });

  final int aMinutes;
  final int bMinutes;
  final int cMinutes;
  final int fMinutes;

  static const standard = TierReleaseOffsets(
    aMinutes: 0,
    bMinutes: 30,
    cMinutes: 60,
    fMinutes: 180,
  );

  static const urgent = TierReleaseOffsets(
    aMinutes: 0,
    bMinutes: 15,
    cMinutes: 30,
    fMinutes: 60,
  );

  static const emergency = TierReleaseOffsets(
    aMinutes: 0,
    bMinutes: 5,
    cMinutes: 10,
    fMinutes: 15,
  );

  static TierReleaseOffsets presetFor(TierStrategy strategy) {
    switch (strategy) {
      case TierStrategy.standard:
        return standard;
      case TierStrategy.urgent:
        return urgent;
      case TierStrategy.emergency:
        return emergency;
      case TierStrategy.custom:
        throw ArgumentError('Custom tier schedules must provide offsets.');
    }
  }

  bool get isValid =>
      aMinutes >= 0 &&
      aMinutes <= bMinutes &&
      bMinutes <= cMinutes &&
      cMinutes <= fMinutes;

  Map<String, dynamic> toConfigureRpcParams(String eventId) => {
    'p_event_id': eventId,
    'p_a_offset_minutes': aMinutes,
    'p_b_offset_minutes': bMinutes,
    'p_c_offset_minutes': cMinutes,
    'p_f_offset_minutes': fMinutes,
    'p_reason': 'Configured from admin event form',
  };
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
    this.confirmedCount = 0,
    this.waitlistCount = 0,
    this.vacantCount,
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
  final int confirmedCount;
  final int waitlistCount;
  final int? vacantCount;

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
      confirmedCount: (json['confirmed_count'] as num?)?.toInt() ?? 0,
      waitlistCount: (json['waitlist_count'] as num?)?.toInt() ?? 0,
      vacantCount: (json['vacant_count'] as num?)?.toInt(),
    );
  }
}

class EventLeaderInput {
  const EventLeaderInput({required this.userId, required this.leaderRole});

  final String userId;
  final String leaderRole;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'leader_role': leaderRole,
  };
}

class EventRequirementInput {
  const EventRequirementInput({
    required this.name,
    this.description,
    this.isMandatory = true,
    this.acknowledgementRequired = false,
    this.extraAllowanceAmount = 0,
    this.displayOrder = 0,
  });

  final String name;
  final String? description;
  final bool isMandatory;
  final bool acknowledgementRequired;
  final double extraAllowanceAmount;
  final int displayOrder;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'is_mandatory': isMandatory,
    'acknowledgement_required': acknowledgementRequired,
    'extra_allowance_amount': extraAllowanceAmount,
    'display_order': displayOrder,
  };
}

class EventAllowanceInput {
  const EventAllowanceInput({
    required this.label,
    this.description,
    required this.amount,
    this.displayOrder = 0,
  });

  final String label;
  final String? description;
  final double amount;
  final int displayOrder;

  Map<String, dynamic> toJson() => {
    'label': label,
    'description': description,
    'amount': amount,
    'display_order': displayOrder,
  };
}

class AdminEventDetail {
  const AdminEventDetail({
    required this.summary,
    required this.mapsUrl,
    required this.workStartsAt,
    required this.expectedEndsAt,
    required this.instructions,
    required this.dressCode,
    required this.confirmedCount,
    required this.waitlistCount,
    required this.openReviewFlags,
    required this.leaders,
    required this.requirements,
    required this.allowances,
  });

  final EventSummary summary;
  final String? mapsUrl;
  final DateTime workStartsAt;
  final DateTime expectedEndsAt;
  final String? instructions;
  final String? dressCode;
  final int confirmedCount;
  final int waitlistCount;
  final int openReviewFlags;
  final List<AdminEventLeader> leaders;
  final List<AdminEventRequirement> requirements;
  final List<AdminEventAllowance> allowances;

  static AdminEventDetail fromJson(Map<String, dynamic> json) {
    return AdminEventDetail(
      summary: EventSummary.fromJson(json),
      mapsUrl: json['maps_url'] as String?,
      workStartsAt: DateTime.parse(json['work_starts_at'] as String),
      expectedEndsAt: DateTime.parse(json['expected_ends_at'] as String),
      instructions: json['instructions'] as String?,
      dressCode: json['dress_code'] as String?,
      confirmedCount: (json['confirmed_count'] as num?)?.toInt() ?? 0,
      waitlistCount: (json['waitlist_count'] as num?)?.toInt() ?? 0,
      openReviewFlags: (json['open_review_flags'] as num?)?.toInt() ?? 0,
      leaders: ((json['leaders'] as List?) ?? [])
          .map(
            (row) => AdminEventLeader.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
      requirements: ((json['requirements'] as List?) ?? [])
          .map(
            (row) => AdminEventRequirement.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
      allowances: ((json['allowances'] as List?) ?? [])
          .map(
            (row) => AdminEventAllowance.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
    );
  }

  EventDraftInput toDraftInput() {
    return EventDraftInput(
      title: summary.title,
      eventType: summary.eventType,
      venueName: summary.venueName,
      mapsUrl: mapsUrl,
      reportingAt: summary.reportingAt,
      workStartsAt: workStartsAt,
      expectedEndsAt: expectedEndsAt,
      requiredWorkerCount: summary.requiredWorkerCount,
      dailyWage: summary.dailyWage,
      tierStrategy: summary.tierStrategy,
      instructions: instructions,
      dressCode: dressCode,
      leaders: leaders
          .map(
            (leader) => EventLeaderInput(
              userId: leader.userId,
              leaderRole: leader.leaderRole,
            ),
          )
          .toList(),
      requirements: requirements
          .map(
            (requirement) => EventRequirementInput(
              name: requirement.name,
              description: requirement.description,
              isMandatory: requirement.isMandatory,
              acknowledgementRequired: requirement.acknowledgementRequired,
              extraAllowanceAmount: requirement.extraAllowanceAmount,
              displayOrder: requirement.displayOrder,
            ),
          )
          .toList(),
      allowances: allowances
          .map(
            (allowance) => EventAllowanceInput(
              label: allowance.label,
              description: allowance.description,
              amount: allowance.amount,
              displayOrder: allowance.displayOrder,
            ),
          )
          .toList(),
    );
  }
}

class AdminEventLeader {
  const AdminEventLeader({
    required this.userId,
    required this.fullName,
    required this.leaderRole,
  });

  final String userId;
  final String fullName;
  final String leaderRole;

  static AdminEventLeader fromJson(Map<String, dynamic> json) {
    return AdminEventLeader(
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String,
      leaderRole: json['leader_role'] as String,
    );
  }
}

class AdminEventRequirement {
  const AdminEventRequirement({
    required this.name,
    this.description,
    required this.isMandatory,
    required this.acknowledgementRequired,
    required this.extraAllowanceAmount,
    required this.displayOrder,
  });

  final String name;
  final String? description;
  final bool isMandatory;
  final bool acknowledgementRequired;
  final double extraAllowanceAmount;
  final int displayOrder;

  static AdminEventRequirement fromJson(Map<String, dynamic> json) {
    return AdminEventRequirement(
      name: json['name'] as String,
      description: json['description'] as String?,
      isMandatory: json['is_mandatory'] as bool? ?? true,
      acknowledgementRequired:
          json['acknowledgement_required'] as bool? ?? false,
      extraAllowanceAmount:
          (json['extra_allowance_amount'] as num?)?.toDouble() ?? 0,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminEventAllowance {
  const AdminEventAllowance({
    required this.label,
    this.description,
    required this.amount,
    required this.displayOrder,
  });

  final String label;
  final String? description;
  final double amount;
  final int displayOrder;

  static AdminEventAllowance fromJson(Map<String, dynamic> json) {
    return AdminEventAllowance(
      label: json['label'] as String,
      description: json['description'] as String?,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminEventDashboard {
  const AdminEventDashboard({
    required this.todayEventCount,
    required this.draftCount,
    required this.publishedCount,
    required this.upcomingCount,
    required this.inProgressCount,
    required this.completedCount,
    required this.openReviewFlagCount,
    required this.requiredTodayCount,
    required this.confirmedTodayCount,
    required this.vacantTodayCount,
  });

  final int todayEventCount;
  final int draftCount;
  final int publishedCount;
  final int upcomingCount;
  final int inProgressCount;
  final int completedCount;
  final int openReviewFlagCount;
  final int requiredTodayCount;
  final int confirmedTodayCount;
  final int vacantTodayCount;

  static AdminEventDashboard fromJson(Map<String, dynamic> json) {
    return AdminEventDashboard(
      todayEventCount: (json['today_event_count'] as num).toInt(),
      draftCount: (json['draft_count'] as num).toInt(),
      publishedCount: (json['published_count'] as num).toInt(),
      upcomingCount: (json['upcoming_count'] as num).toInt(),
      inProgressCount: (json['in_progress_count'] as num).toInt(),
      completedCount: (json['completed_count'] as num).toInt(),
      openReviewFlagCount: (json['open_review_flag_count'] as num).toInt(),
      requiredTodayCount: (json['required_today_count'] as num).toInt(),
      confirmedTodayCount: (json['confirmed_today_count'] as num).toInt(),
      vacantTodayCount: (json['vacant_today_count'] as num).toInt(),
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
    this.customTierOffsets,
    this.mapsUrl,
    this.instructions,
    this.dressCode,
    this.leaders = const [],
    this.requirements = const [],
    this.allowances = const [],
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
  final TierReleaseOffsets? customTierOffsets;
  final String? instructions;
  final String? dressCode;
  final List<EventLeaderInput> leaders;
  final List<EventRequirementInput> requirements;
  final List<EventAllowanceInput> allowances;

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
    'p_leaders': leaders.map((leader) => leader.toJson()).toList(),
    'p_requirements': requirements
        .map((requirement) => requirement.toJson())
        .toList(),
    'p_allowances': allowances.map((allowance) => allowance.toJson()).toList(),
  };

  Map<String, dynamic> toUpdateRpcParams({
    required String eventId,
    required int expectedVersion,
    required String reason,
    bool confirmConflicts = false,
  }) => {
    'p_event_id': eventId,
    'p_expected_version': expectedVersion,
    ...toCreateRpcParams(),
    'p_reason': reason,
    'p_confirm_conflicts': confirmConflicts,
  };
}

String describeTierReleaseOffsets(TierReleaseOffsets offsets) {
  return 'A ${offsets.aMinutes}m, B ${offsets.bMinutes}m, '
      'C ${offsets.cMinutes}m, F ${offsets.fMinutes}m';
}

Duration timeUntilTierOpens({
  required DateTime opensAt,
  required DateTime now,
}) {
  final remaining = opensAt.difference(now);
  return remaining.isNegative ? Duration.zero : remaining;
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
