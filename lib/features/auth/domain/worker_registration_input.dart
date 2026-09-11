import 'phone_number.dart';

enum WorkerRegistrationType {
  newWorker,
  oldWorker;

  String get databaseValue {
    switch (this) {
      case WorkerRegistrationType.newWorker:
        return 'NEW_WORKER';
      case WorkerRegistrationType.oldWorker:
        return 'OLD_WORKER';
    }
  }
}

enum WorkerExperienceLevel {
  noExperience,
  someExperience,
  highlyExperienced;

  String get databaseValue {
    switch (this) {
      case WorkerExperienceLevel.noExperience:
        return 'NO_EXPERIENCE';
      case WorkerExperienceLevel.someExperience:
        return 'SOME_EXPERIENCE';
      case WorkerExperienceLevel.highlyExperienced:
        return 'HIGHLY_EXPERIENCED';
    }
  }

  String get label {
    switch (this) {
      case WorkerExperienceLevel.noExperience:
        return 'No experience';
      case WorkerExperienceLevel.someExperience:
        return 'Some experience';
      case WorkerExperienceLevel.highlyExperienced:
        return 'Highly experienced';
    }
  }
}

enum RegistrationWorkerCategory {
  a,
  b,
  c,
  f;

  String get databaseValue => name.toUpperCase();
  String get label => databaseValue;
}

class WorkerRegistrationInput {
  const WorkerRegistrationInput({
    required this.registrationType,
    required this.fullName,
    required this.phone,
    required this.password,
    required this.profilePhotoPath,
    required this.idCardFilePath,
    required this.dateOfBirth,
    required this.place,
    required this.heightCm,
    required this.educationStatus,
    required this.experienceLevel,
    required this.privacyTermsVersion,
    this.requestedCategory,
  });

  final WorkerRegistrationType registrationType;
  final String fullName;
  final PhoneNumber phone;
  final String password;
  final String profilePhotoPath;
  final String idCardFilePath;
  final DateTime dateOfBirth;
  final String place;
  final double heightCm;
  final String educationStatus;
  final WorkerExperienceLevel experienceLevel;
  final String privacyTermsVersion;
  final RegistrationWorkerCategory? requestedCategory;

  int completeYearsAt(DateTime now) {
    var age = now.year - dateOfBirth.year;
    final birthdayThisYear = DateTime(
      now.year,
      dateOfBirth.month,
      dateOfBirth.day,
    );
    if (birthdayThisYear.isAfter(DateTime(now.year, now.month, now.day))) {
      age--;
    }
    return age;
  }

  Map<String, dynamic> toRpcParams() {
    return {
      'full_name': fullName.trim(),
      'phone_e164': phone.value,
      'profile_photo_path': profilePhotoPath,
      'id_card_file_path': idCardFilePath,
      'date_of_birth': dateOfBirth.toIso8601String().split('T').first,
      'native_place': place.trim(),
      'height_cm': heightCm,
      'education_status': educationStatus.trim(),
      'experience_level': experienceLevel.databaseValue,
      'registration_type': registrationType.databaseValue,
      'p_requested_category': requestedCategory?.databaseValue,
      'privacy_terms_version': privacyTermsVersion.trim(),
    };
  }

  void validate() {
    if (completeYearsAt(DateTime.now()) < 18) {
      throw const FormatException(
        'You must be at least 18 years old to register.',
      );
    }
    if (registrationType == WorkerRegistrationType.newWorker &&
        requestedCategory != null) {
      throw const FormatException('New workers are registered in F category.');
    }
    if (registrationType == WorkerRegistrationType.oldWorker &&
        requestedCategory == null) {
      throw const FormatException('Choose the old worker category.');
    }
    if (fullName.trim().isEmpty ||
        password.length < 6 ||
        profilePhotoPath.trim().isEmpty ||
        idCardFilePath.trim().isEmpty ||
        place.trim().isEmpty ||
        heightCm <= 0 ||
        educationStatus.trim().isEmpty ||
        privacyTermsVersion.trim().isEmpty) {
      throw const FormatException('All required fields must be complete.');
    }
  }
}
