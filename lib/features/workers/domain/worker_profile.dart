import '../../auth/application/auth_session.dart';

enum WorkerCategory {
  a,
  b,
  c,
  f;

  static WorkerCategory? fromDatabase(String? value) {
    switch (value) {
      case 'A':
        return WorkerCategory.a;
      case 'B':
        return WorkerCategory.b;
      case 'C':
        return WorkerCategory.c;
      case 'F':
        return WorkerCategory.f;
      case null:
        return null;
      default:
        throw FormatException('Unknown worker category "$value".');
    }
  }

  String get databaseValue => name.toUpperCase();
  String get label => databaseValue;

  int get rank {
    switch (this) {
      case WorkerCategory.a:
        return 1;
      case WorkerCategory.b:
        return 2;
      case WorkerCategory.c:
        return 3;
      case WorkerCategory.f:
        return 4;
    }
  }

  List<WorkerCategory> get oneStepOptions {
    return WorkerCategory.values
        .where((category) => (category.rank - rank).abs() == 1)
        .toList(growable: false);
  }
}

enum AccountStatus {
  active,
  suspended,
  detained,
  blacklisted,
  inactive,
  pendingApproval,
  rejected;

  static AccountStatus fromDatabase(String value) {
    switch (value) {
      case 'ACTIVE':
        return AccountStatus.active;
      case 'SUSPENDED':
        return AccountStatus.suspended;
      case 'DETAINED':
        return AccountStatus.detained;
      case 'BLACKLISTED':
        return AccountStatus.blacklisted;
      case 'INACTIVE':
        return AccountStatus.inactive;
      case 'PENDING_APPROVAL':
        return AccountStatus.pendingApproval;
      case 'REJECTED':
        return AccountStatus.rejected;
      default:
        throw FormatException('Unknown account status "$value".');
    }
  }

  String get databaseValue {
    switch (this) {
      case AccountStatus.active:
        return 'ACTIVE';
      case AccountStatus.suspended:
        return 'SUSPENDED';
      case AccountStatus.detained:
        return 'DETAINED';
      case AccountStatus.blacklisted:
        return 'BLACKLISTED';
      case AccountStatus.inactive:
        return 'INACTIVE';
      case AccountStatus.pendingApproval:
        return 'PENDING_APPROVAL';
      case AccountStatus.rejected:
        return 'REJECTED';
    }
  }

  String get label {
    switch (this) {
      case AccountStatus.active:
        return 'Active';
      case AccountStatus.suspended:
        return 'Suspended';
      case AccountStatus.detained:
        return 'Detained';
      case AccountStatus.blacklisted:
        return 'Blacklisted';
      case AccountStatus.inactive:
        return 'Inactive';
      case AccountStatus.pendingApproval:
        return 'Pending approval';
      case AccountStatus.rejected:
        return 'Rejected';
    }
  }
}

class WorkerDirectoryQuery {
  const WorkerDirectoryQuery({
    this.searchText,
    this.accountStatus,
    this.category,
    this.limit = 50,
    this.offset = 0,
  });

  final String? searchText;
  final AccountStatus? accountStatus;
  final WorkerCategory? category;
  final int limit;
  final int offset;

  WorkerDirectoryQuery copyWith({
    String? searchText,
    AccountStatus? accountStatus,
    WorkerCategory? category,
    int? limit,
    int? offset,
    bool clearAccountStatus = false,
    bool clearCategory = false,
  }) {
    return WorkerDirectoryQuery(
      searchText: searchText ?? this.searchText,
      accountStatus: clearAccountStatus
          ? null
          : accountStatus ?? this.accountStatus,
      category: clearCategory ? null : category ?? this.category,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
    );
  }
}

class WorkerProfile {
  const WorkerProfile({
    required this.userId,
    required this.fullName,
    required this.initials,
    required this.phoneE164,
    required this.role,
    required this.accountStatus,
    required this.lastWorkerCategory,
    this.workerNumber,
    this.profilePhotoPath,
    this.category,
    this.reliabilityScore,
    this.reliabilityState = ReliabilityState.provisional,
    this.reliabilitySampleCount = 0,
    this.reliabilityPresentCount = 0,
    this.reliabilityLateCount = 0,
    this.reliabilityAbsentCount = 0,
    this.reliabilityWorkerCancellationCount = 0,
    this.reliabilityCompletedEventCount = 0,
    this.reliabilityPerformanceEventCount = 0,
    this.reliabilityPerformanceAverage,
    this.reliabilityConfigVersion,
    this.reliabilityComputedAt,
    this.profileCompletedAt,
    this.dateOfBirth,
    this.address,
    this.nativePlace,
    this.heightCm,
    this.educationStatus,
    this.hasPreviousExperience,
    this.experienceDetails,
    this.registrationType,
    this.requestedCategory,
    this.idCardFilePath,
    this.experienceLevel,
  });

  final String userId;
  final int? workerNumber;
  final String fullName;
  final String initials;
  final String phoneE164;
  final String? profilePhotoPath;
  final AppRole role;
  final AccountStatus accountStatus;
  final WorkerCategory? category;
  final WorkerCategory lastWorkerCategory;
  final double? reliabilityScore;
  final ReliabilityState reliabilityState;
  final int reliabilitySampleCount;
  final int reliabilityPresentCount;
  final int reliabilityLateCount;
  final int reliabilityAbsentCount;
  final int reliabilityWorkerCancellationCount;
  final int reliabilityCompletedEventCount;
  final int reliabilityPerformanceEventCount;
  final double? reliabilityPerformanceAverage;
  final int? reliabilityConfigVersion;
  final DateTime? reliabilityComputedAt;
  final DateTime? profileCompletedAt;
  final DateTime? dateOfBirth;
  final String? address;
  final String? nativePlace;
  final double? heightCm;
  final String? educationStatus;
  final bool? hasPreviousExperience;
  final String? experienceDetails;
  final String? registrationType;
  final WorkerCategory? requestedCategory;
  final String? idCardFilePath;
  final String? experienceLevel;

  bool get isComplete => profileCompletedAt != null;

  String get registrationTypeLabel {
    switch (registrationType) {
      case 'NEW_WORKER':
        return 'New worker';
      case 'OLD_WORKER':
        return 'Old worker';
      case null:
        return '-';
      default:
        return registrationType!;
    }
  }

  String get experienceLevelLabel {
    switch (experienceLevel) {
      case 'NO_EXPERIENCE':
        return 'No experience';
      case 'SOME_EXPERIENCE':
        return 'Some experience';
      case 'HIGHLY_EXPERIENCED':
        return 'Highly experienced';
      case null:
        return hasPreviousExperience == null
            ? '-'
            : hasPreviousExperience!
            ? 'Some experience'
            : 'No experience';
      default:
        return experienceLevel!;
    }
  }

  int? completeYearsOld({DateTime? at}) {
    final dob = dateOfBirth;
    if (dob == null) return null;
    final now = at ?? DateTime.now();
    var age = now.year - dob.year;
    final birthdayThisYear = DateTime(now.year, dob.month, dob.day);
    if (birthdayThisYear.isAfter(DateTime(now.year, now.month, now.day))) {
      age--;
    }
    return age;
  }

  static WorkerProfile fromJson(Map<String, dynamic> json) {
    final workerNumberValue = json['worker_number'];
    final reliabilityValue = json['reliability_score'];
    final performanceAverageValue = json['reliability_performance_average'];
    final heightValue = json['height_cm'];

    return WorkerProfile(
      userId: json['user_id'] as String? ?? json['id'] as String,
      workerNumber: workerNumberValue == null
          ? null
          : (workerNumberValue as num).toInt(),
      fullName: json['full_name'] as String,
      initials: json['initials'] as String,
      phoneE164: json['phone_e164'] as String,
      profilePhotoPath: json['profile_photo_path'] as String?,
      role: AppRoleParsing.fromDatabase(json['role'] as String),
      accountStatus: AccountStatus.fromDatabase(
        json['account_status'] as String,
      ),
      category: WorkerCategory.fromDatabase(json['category'] as String?),
      lastWorkerCategory: WorkerCategory.fromDatabase(
        json['last_worker_category'] as String?,
      )!,
      reliabilityScore: reliabilityValue == null
          ? null
          : (reliabilityValue as num).toDouble(),
      reliabilityState: ReliabilityState.fromDatabase(
        json['reliability_state'] as String? ?? 'PROVISIONAL',
      ),
      reliabilitySampleCount:
          (json['reliability_sample_count'] as num?)?.toInt() ?? 0,
      reliabilityPresentCount:
          (json['reliability_present_count'] as num?)?.toInt() ?? 0,
      reliabilityLateCount:
          (json['reliability_late_count'] as num?)?.toInt() ?? 0,
      reliabilityAbsentCount:
          (json['reliability_absent_count'] as num?)?.toInt() ?? 0,
      reliabilityWorkerCancellationCount:
          (json['reliability_worker_cancellation_count'] as num?)?.toInt() ?? 0,
      reliabilityCompletedEventCount:
          (json['reliability_completed_event_count'] as num?)?.toInt() ?? 0,
      reliabilityPerformanceEventCount:
          (json['reliability_performance_event_count'] as num?)?.toInt() ?? 0,
      reliabilityPerformanceAverage: performanceAverageValue == null
          ? null
          : (performanceAverageValue as num).toDouble(),
      reliabilityConfigVersion: (json['reliability_config_version'] as num?)
          ?.toInt(),
      reliabilityComputedAt: json['reliability_computed_at'] == null
          ? null
          : DateTime.parse(json['reliability_computed_at'] as String),
      profileCompletedAt: json['profile_completed_at'] == null
          ? null
          : DateTime.parse(json['profile_completed_at'] as String),
      dateOfBirth: json['date_of_birth'] == null
          ? null
          : DateTime.parse(json['date_of_birth'] as String),
      address: json['address'] as String?,
      nativePlace: json['native_place'] as String?,
      heightCm: heightValue == null ? null : (heightValue as num).toDouble(),
      educationStatus: json['education_status'] as String?,
      hasPreviousExperience: json['has_previous_experience'] as bool?,
      experienceDetails: json['experience_details'] as String?,
      registrationType: json['registration_type'] as String?,
      requestedCategory: WorkerCategory.fromDatabase(
        json['requested_category'] as String?,
      ),
      idCardFilePath: json['id_card_file_path'] as String?,
      experienceLevel: json['experience_level'] as String?,
    );
  }
}

enum ReliabilityState {
  provisional,
  rated;

  static ReliabilityState fromDatabase(String value) {
    switch (value) {
      case 'PROVISIONAL':
        return ReliabilityState.provisional;
      case 'RATED':
        return ReliabilityState.rated;
      default:
        throw FormatException('Unknown reliability state "$value".');
    }
  }

  String get databaseValue {
    switch (this) {
      case ReliabilityState.provisional:
        return 'PROVISIONAL';
      case ReliabilityState.rated:
        return 'RATED';
    }
  }

  String label(int sampleCount) {
    switch (this) {
      case ReliabilityState.provisional:
        return 'Provisional - $sampleCount of 3 commitments';
      case ReliabilityState.rated:
        return 'Rated';
    }
  }
}

class WorkerHistoryEntry {
  const WorkerHistoryEntry({
    required this.historyType,
    required this.action,
    required this.actorRole,
    required this.reason,
    required this.createdAt,
    this.oldValue,
    this.newValue,
  });

  final String historyType;
  final String action;
  final String? oldValue;
  final String? newValue;
  final AppRole? actorRole;
  final String reason;
  final DateTime createdAt;

  static WorkerHistoryEntry fromJson(Map<String, dynamic> json) {
    return WorkerHistoryEntry(
      historyType: json['history_type'] as String,
      action: json['action'] as String,
      oldValue: json['old_value'] as String?,
      newValue: json['new_value'] as String?,
      actorRole: json['actor_role'] == null
          ? null
          : AppRoleParsing.fromDatabase(json['actor_role'] as String),
      reason: json['reason'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class WorkerCategoryChangeResult {
  const WorkerCategoryChangeResult({
    required this.workerId,
    required this.oldCategory,
    required this.newCategory,
  });

  final String workerId;
  final WorkerCategory oldCategory;
  final WorkerCategory newCategory;

  static WorkerCategoryChangeResult fromJson(Map<String, dynamic> json) {
    return WorkerCategoryChangeResult(
      workerId: json['worker_id'] as String,
      oldCategory: WorkerCategory.fromDatabase(
        json['old_category'] as String?,
      )!,
      newCategory: WorkerCategory.fromDatabase(
        json['new_category'] as String?,
      )!,
    );
  }
}

class WorkerProfileUpdate {
  const WorkerProfileUpdate({
    required this.fullName,
    required this.initials,
    required this.address,
    required this.nativePlace,
    required this.heightCm,
    required this.educationStatus,
    required this.hasPreviousExperience,
    this.experienceDetails,
    this.profilePhotoPath,
  });

  final String fullName;
  final String initials;
  final String address;
  final String nativePlace;
  final double heightCm;
  final String educationStatus;
  final bool hasPreviousExperience;
  final String? experienceDetails;
  final String? profilePhotoPath;

  Map<String, dynamic> toRpcParams() => {
    'p_full_name': fullName,
    'p_initials': initials,
    'p_address': address,
    'p_native_place': nativePlace,
    'p_height_cm': heightCm,
    'p_education_status': educationStatus,
    'p_has_previous_experience': hasPreviousExperience,
    'p_experience_details': experienceDetails,
    'p_profile_photo_path': profilePhotoPath,
  };
}

class StaffProfile {
  const StaffProfile({
    required this.userId,
    required this.fullName,
    required this.initials,
    required this.phoneE164,
    required this.role,
    required this.accountStatus,
    this.profileCompletedAt,
  });

  final String userId;
  final String fullName;
  final String initials;
  final String phoneE164;
  final AppRole role;
  final AccountStatus accountStatus;
  final DateTime? profileCompletedAt;

  static StaffProfile fromJson(Map<String, dynamic> json) {
    return StaffProfile(
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String,
      initials: json['initials'] as String,
      phoneE164: json['phone_e164'] as String,
      role: AppRoleParsing.fromDatabase(json['role'] as String),
      accountStatus: AccountStatus.fromDatabase(
        json['account_status'] as String,
      ),
      profileCompletedAt: json['profile_completed_at'] == null
          ? null
          : DateTime.parse(json['profile_completed_at'] as String),
    );
  }
}

class StaffProvisionRequest {
  const StaffProvisionRequest({
    required this.fullName,
    required this.initials,
    required this.email,
    required this.phoneE164,
    required this.password,
    required this.role,
    required this.reason,
  });

  final String fullName;
  final String initials;
  final String email;
  final String phoneE164;
  final String password;
  final AppRole role;
  final String reason;

  Map<String, dynamic> toFunctionBody() => {
    'action': 'provision_staff',
    'email': email.trim().toLowerCase(),
    'phone': phoneE164,
    'password': password,
    'full_name': fullName,
    'initials': initials,
    'role': role.databaseValue,
    'reason': reason,
  };
}

class ErasureRequestStatus {
  const ErasureRequestStatus({
    required this.id,
    required this.status,
    required this.verificationStatus,
    required this.dueAt,
    required this.createdAt,
    required this.photoCleanupStatus,
    this.completedAt,
    this.completionNotes,
  });

  final String id;
  final String status;
  final String verificationStatus;
  final DateTime dueAt;
  final DateTime createdAt;
  final String photoCleanupStatus;
  final DateTime? completedAt;
  final String? completionNotes;

  static ErasureRequestStatus fromJson(Map<String, dynamic> json) {
    return ErasureRequestStatus(
      id: json['request_id'] as String,
      status: json['status'] as String,
      verificationStatus: json['verification_status'] as String,
      dueAt: DateTime.parse(json['due_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      photoCleanupStatus: json['photo_cleanup_status'] as String,
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
      completionNotes: json['completion_notes'] as String?,
    );
  }

  bool get isOpen =>
      status == 'OPEN' || status == 'VERIFIED' || status == 'LEGAL_HOLD';

  String get label {
    if (status == 'COMPLETED') return 'Completed';
    if (status == 'REJECTED') return 'Rejected';
    if (status == 'LEGAL_HOLD') return 'Paused for legal hold';
    if (verificationStatus == 'PENDING_VERIFICATION') {
      return 'Pending verification';
    }
    if (status == 'VERIFIED') return 'Verified, due for fulfillment';
    return status;
  }
}
