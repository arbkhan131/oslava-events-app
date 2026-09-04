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
}

enum AccountStatus {
  active,
  suspended,
  detained,
  blacklisted,
  inactive;

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
      default:
        throw FormatException('Unknown account status "$value".');
    }
  }

  String get databaseValue => name.toUpperCase();
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
    this.profileCompletedAt,
    this.dateOfBirth,
    this.address,
    this.nativePlace,
    this.heightCm,
    this.educationStatus,
    this.hasPreviousExperience,
    this.experienceDetails,
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
  final DateTime? profileCompletedAt;
  final DateTime? dateOfBirth;
  final String? address;
  final String? nativePlace;
  final double? heightCm;
  final String? educationStatus;
  final bool? hasPreviousExperience;
  final String? experienceDetails;

  bool get isComplete => profileCompletedAt != null;

  static WorkerProfile fromJson(Map<String, dynamic> json) {
    final workerNumberValue = json['worker_number'];
    final reliabilityValue = json['reliability_score'];
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
    );
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
