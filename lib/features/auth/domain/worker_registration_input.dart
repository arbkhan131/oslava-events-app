import 'phone_number.dart';

class WorkerRegistrationInput {
  const WorkerRegistrationInput({
    required this.fullName,
    required this.initials,
    required this.phone,
    required this.password,
    required this.profilePhotoPath,
    required this.dateOfBirth,
    required this.address,
    required this.nativePlace,
    required this.heightCm,
    required this.educationStatus,
    required this.hasPreviousExperience,
    this.experienceDetails,
  });

  final String fullName;
  final String initials;
  final PhoneNumber phone;
  final String password;
  final String profilePhotoPath;
  final DateTime dateOfBirth;
  final String address;
  final String nativePlace;
  final double heightCm;
  final String educationStatus;
  final bool hasPreviousExperience;
  final String? experienceDetails;

  Map<String, dynamic> toRpcParams() {
    return {
      'full_name': fullName.trim(),
      'initials': initials.trim(),
      'profile_photo_path': profilePhotoPath,
      'date_of_birth': dateOfBirth.toIso8601String().split('T').first,
      'address': address.trim(),
      'native_place': nativePlace.trim(),
      'height_cm': heightCm,
      'education_status': educationStatus.trim(),
      'has_previous_experience': hasPreviousExperience,
      'experience_details': experienceDetails?.trim(),
    };
  }

  void validate() {
    if (fullName.trim().isEmpty ||
        initials.trim().isEmpty ||
        password.length < 6 ||
        profilePhotoPath.trim().isEmpty ||
        address.trim().isEmpty ||
        nativePlace.trim().isEmpty ||
        heightCm <= 0 ||
        educationStatus.trim().isEmpty) {
      throw const FormatException('All required fields must be complete.');
    }
  }
}
