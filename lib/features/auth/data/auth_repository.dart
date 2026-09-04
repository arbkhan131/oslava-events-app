import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/bootstrap.dart';
import '../application/auth_session.dart';
import '../domain/auth_failure.dart';
import '../domain/phone_number.dart';
import '../domain/prepared_profile_photo.dart';
import '../domain/worker_registration_input.dart';
import 'profile_photo_preparer.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(
    ref.watch(supabaseClientProvider),
    const ProfilePhotoPreparer(),
  ),
);

abstract interface class AuthRepository {
  Future<AppSession> signInWithPhonePassword({
    required PhoneNumber phone,
    required String password,
  });

  Future<AppSession> registerWorker({
    required WorkerRegistrationInput input,
    required Uint8List profilePhotoBytes,
    required String profilePhotoMimeType,
  });

  Future<void> startPasswordRecovery({
    required PhoneNumber phone,
    required String environmentName,
  });

  Future<void> verifyRecoveryOtpAndSetPassword({
    required PhoneNumber phone,
    required String otp,
    required String newPassword,
  });

  Future<void> signOut();

  Future<AppSession?> loadCurrentSession();
}

class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository(this._client, this._photoPreparer);

  final SupabaseClient _client;
  final ProfilePhotoPreparer _photoPreparer;

  @override
  Future<AppSession> signInWithPhonePassword({
    required PhoneNumber phone,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      phone: phone.value,
      password: password,
    );

    return _loadCurrentProfile();
  }

  @override
  Future<AppSession> registerWorker({
    required WorkerRegistrationInput input,
    required Uint8List profilePhotoBytes,
    required String profilePhotoMimeType,
  }) async {
    input.validate();

    final authResponse = await _client.auth.signUp(
      phone: input.phone.value,
      password: input.password,
    );

    final userId = authResponse.user?.id;
    if (userId == null) {
      throw const AuthFailure('Registration did not return a user.');
    }

    final photo = _photoPreparer.prepare(
      userId: userId,
      sourceBytes: profilePhotoBytes,
      mimeType: profilePhotoMimeType,
    );

    await _uploadProfilePhoto(photo);

    final rpcInput = WorkerRegistrationInput(
      fullName: input.fullName,
      initials: input.initials,
      phone: input.phone,
      password: input.password,
      profilePhotoPath: photo.storagePath,
      dateOfBirth: input.dateOfBirth,
      address: input.address,
      nativePlace: input.nativePlace,
      heightCm: input.heightCm,
      educationStatus: input.educationStatus,
      hasPreviousExperience: input.hasPreviousExperience,
      experienceDetails: input.experienceDetails,
    );

    await _client.rpc(
      'complete_worker_registration',
      params: rpcInput.toRpcParams(),
    );

    return _loadCurrentProfile();
  }

  @override
  Future<void> startPasswordRecovery({
    required PhoneNumber phone,
    required String environmentName,
  }) async {
    await _client.rpc(
      'start_password_recovery',
      params: {
        'recovery_phone_e164': phone.value,
        'provider_environment': environmentName,
      },
    );

    await _client.auth.signInWithOtp(phone: phone.value);
  }

  @override
  Future<void> verifyRecoveryOtpAndSetPassword({
    required PhoneNumber phone,
    required String otp,
    required String newPassword,
  }) async {
    await _client.auth.verifyOTP(
      phone: phone.value,
      token: otp,
      type: OtpType.sms,
    );
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<AppSession?> loadCurrentSession() async {
    if (_client.auth.currentSession == null) {
      return null;
    }

    return _loadCurrentProfile();
  }

  Future<void> _uploadProfilePhoto(PreparedProfilePhoto photo) {
    return _client.storage
        .from('profile-photos')
        .uploadBinary(
          photo.storagePath,
          photo.bytes,
          fileOptions: FileOptions(contentType: photo.mimeType, upsert: true),
        );
  }

  Future<AppSession> _loadCurrentProfile() async {
    final response = await _client.rpc('my_profile').single();
    final profile = Map<String, dynamic>.from(response as Map);

    return AppSession(
      userId: profile['id'] as String,
      role: AppRoleParsing.fromDatabase(profile['role'] as String),
      displayName: profile['full_name'] as String,
    );
  }
}
