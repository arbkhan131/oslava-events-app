import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/bootstrap.dart';
import '../application/auth_session.dart';
import '../domain/auth_failure.dart';
import '../domain/email_address.dart';
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
  Stream<void> get sessionChanges;
  String? get registrationEmail;
  String? get registrationPhone;
  Map<String, dynamic> get registrationDraft;
  Future<Map<String, dynamic>> loadPrivacyTerms();
  Future<void> verifyRegistrationOtp(String otp);
  Future<void> resendRegistrationOtp();
  Future<AppSession> signInWithEmailPassword({
    required EmailAddress email,
    required String password,
  });
  Future<AppSession> signInWithPhonePassword({
    required PhoneNumber phone,
    required String password,
  });

  Future<AppSession> registerWorker({
    required WorkerRegistrationInput input,
    required Uint8List profilePhotoBytes,
    required String profilePhotoMimeType,
    required Uint8List idCardBytes,
    required String idCardFileName,
    required String idCardMimeType,
  });

  Future<void> startPasswordRecovery({
    required EmailAddress email,
    required String environmentName,
  });

  Future<void> verifyRecoveryOtpAndSetPassword({
    required EmailAddress email,
    required String otp,
    required String newPassword,
  });

  Future<void> signOut();

  Future<AppSession?> loadCurrentSession();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client, this._photoPreparer);

  final SupabaseClient _client;
  final ProfilePhotoPreparer _photoPreparer;
  String? _confirmationEmail;
  @override
  Stream<void> get sessionChanges => _client.auth.onAuthStateChange.map((_) {});

  @override
  String? get registrationEmail {
    final email = _confirmationEmail ?? _client.auth.currentUser?.email;
    return email == null || email.isEmpty ? null : email;
  }

  @override
  String? get registrationPhone {
    final draftPhone = registrationDraft['phone_e164'] as String?;
    return draftPhone == null || draftPhone.isEmpty ? null : draftPhone;
  }

  @override
  Map<String, dynamic> get registrationDraft => Map<String, dynamic>.from(
    _client.auth.currentUser?.userMetadata?['registration_draft'] as Map? ?? {},
  );

  @override
  Future<Map<String, dynamic>> loadPrivacyTerms() async =>
      Map<String, dynamic>.from(
        await _client
            .from('privacy_terms_versions')
            .select('version,summary,published_at')
            .eq('is_active', true)
            .single(),
      );

  @override
  Future<void> verifyRegistrationOtp(String otp) async {
    throw const AuthFailure(
      'Verification codes are not used. Sign in with your WhatsApp number and password.',
    );
  }

  @override
  Future<void> resendRegistrationOtp() async {
    throw const AuthFailure(
      'Verification codes are not used. Sign in with your WhatsApp number and password.',
    );
  }

  @override
  Future<AppSession> signInWithEmailPassword({
    required EmailAddress email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.value,
        password: password,
      );
    } on AuthException catch (error) {
      if (error.code == 'email_not_confirmed') {
        _confirmationEmail = email.value;
        throw const PhoneConfirmationRequired();
      }
      rethrow;
    }

    return _loadCurrentProfile();
  }

  @override
  Future<AppSession> signInWithPhonePassword({
    required PhoneNumber phone,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: phone.authEmail,
      password: password,
    );
    return _loadCurrentProfile();
  }

  @override
  Future<AppSession> registerWorker({
    required WorkerRegistrationInput input,
    required Uint8List profilePhotoBytes,
    required String profilePhotoMimeType,
    required Uint8List idCardBytes,
    required String idCardFileName,
    required String idCardMimeType,
  }) async {
    input.validate();
    if (idCardBytes.isEmpty) {
      throw const FormatException('ID card file is required.');
    }

    final prepared =
        profilePhotoBytes.isEmpty && registrationDraft['photo_ready'] == true
        ? null
        : _photoPreparer.prepare(
            userId: 'validated',
            sourceBytes: profilePhotoBytes,
            mimeType: profilePhotoMimeType,
          );
    final draft = {...input.toRpcParams()}
      ..remove('profile_photo_path')
      ..remove('id_card_file_path');

    await _ensurePhoneAuthSession(input);

    final user = _client.auth.currentUser!;
    if (user.email != input.phone.authEmail) {
      throw const AuthFailure(
        'Sign out before registering a different WhatsApp number.',
      );
    }

    final existing = await _loadCurrentProfile();
    if (existing.profileComplete) {
      return existing;
    }

    final userId = user.id;
    final photoPath = '$userId/profile.jpg';
    final idCardPath = '$userId/${_safeStorageFileName(idCardFileName)}';
    final photo = prepared == null
        ? null
        : PreparedProfilePhoto(
            bytes: prepared.bytes,
            mimeType: prepared.mimeType,
            storagePath: photoPath,
          );

    await _client.auth.updateUser(
      UserAttributes(
        data: {
          'registration_draft': {
            ...draft,
            if (registrationDraft['photo_ready'] == true) 'photo_ready': true,
          },
        },
      ),
    );
    if (photo != null) await _uploadProfilePhoto(photo);
    await _uploadIdCard(
      storagePath: idCardPath,
      bytes: idCardBytes,
      mimeType: idCardMimeType,
    );
    await _client.auth.updateUser(
      UserAttributes(
        data: {
          'registration_draft': {
            ...draft,
            'photo_ready': true,
            'id_card_ready': true,
          },
        },
      ),
    );

    final rpcInput = WorkerRegistrationInput(
      registrationType: input.registrationType,
      fullName: input.fullName,
      phone: input.phone,
      password: input.password,
      profilePhotoPath: photoPath,
      idCardFilePath: idCardPath,
      dateOfBirth: input.dateOfBirth,
      place: input.place,
      heightCm: input.heightCm,
      educationStatus: input.educationStatus,
      experienceLevel: input.experienceLevel,
      requestedCategory: input.requestedCategory,
      privacyTermsVersion: input.privacyTermsVersion,
    );

    final registrationResponse = await _client.rpc(
      'complete_phone_worker_registration',
      params: rpcInput.toRpcParams(),
    );
    try {
      await _client.auth.updateUser(
        UserAttributes(data: {'registration_draft': null}),
      );
    } catch (_) {}
    return _sessionFromRegistrationResult(
      registrationResponse,
      fallbackUserId: userId,
      fallbackDisplayName: input.fullName.trim(),
    );
  }

  AppSession _sessionFromRegistrationResult(
    Object? response, {
    required String fallbackUserId,
    required String fallbackDisplayName,
  }) {
    final row = switch (response) {
      final List<dynamic> rows when rows.isNotEmpty => rows.first,
      final Map<String, dynamic> map => map,
      _ => null,
    };
    if (row is! Map) {
      return AppSession(
        userId: fallbackUserId,
        role: AppRole.worker,
        displayName: fallbackDisplayName,
        accountStatus: 'PENDING_APPROVAL',
      );
    }
    final data = Map<String, dynamic>.from(row);
    return AppSession(
      userId: data['user_id'] as String? ?? fallbackUserId,
      role: AppRoleParsing.fromDatabase(data['role'] as String? ?? 'WORKER'),
      displayName: fallbackDisplayName,
      accountStatus: data['account_status'] as String? ?? 'PENDING_APPROVAL',
      workerNumber: (data['worker_number'] as num?)?.toInt(),
    );
  }

  Future<void> _ensurePhoneAuthSession(WorkerRegistrationInput input) async {
    if (_client.auth.currentSession != null) {
      return;
    }

    try {
      final response = await _client.functions.invoke(
        'create-worker-phone-account',
        body: {'phone': input.phone.value, 'password': input.password},
      );
      if (response.status >= 400) {
        throw AuthFailure(_functionErrorMessage(response.data));
      }
    } on FunctionsHttpException catch (error) {
      if (error.status == 409) {
        await _client.auth.signInWithPassword(
          email: input.phone.authEmail,
          password: input.password,
        );
        return;
      }
      throw AuthFailure(_functionErrorMessage(error.details));
    }

    await _client.auth.signInWithPassword(
      email: input.phone.authEmail,
      password: input.password,
    );
  }

  String _functionErrorMessage(Object? details) {
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    if (details is String && details.trim().isNotEmpty) {
      return details;
    }
    return 'Registration could not be started.';
  }

  @override
  Future<void> startPasswordRecovery({
    required EmailAddress email,
    required String environmentName,
  }) async {
    await _client.auth.resetPasswordForEmail(email.value);
  }

  @override
  Future<void> verifyRecoveryOtpAndSetPassword({
    required EmailAddress email,
    required String otp,
    required String newPassword,
  }) async {
    throw const AuthFailure(
      'Open the reset link from your email to set a new password.',
    );
  }

  @override
  Future<void> signOut() async {
    _confirmationEmail = null;
    await _client.auth.signOut(scope: SignOutScope.local);
  }

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

  Future<void> _uploadIdCard({
    required String storagePath,
    required Uint8List bytes,
    required String mimeType,
  }) {
    return _client.storage
        .from('worker-id-cards')
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );
  }

  String _safeStorageFileName(String name) {
    final trimmed = name.trim().isEmpty ? 'id-card' : name.trim();
    final cleaned = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '$timestamp-$cleaned';
  }

  Future<AppSession> _loadCurrentProfile() async {
    final userId = _client.auth.currentUser!.id;
    final Object? response;
    try {
      response = await _client.rpc('my_profile').maybeSingle();
    } on PostgrestException catch (error) {
      if (_isNoProfileRow(error)) {
        return AppSession(
          userId: userId,
          role: AppRole.worker,
          displayName: 'Finish registration',
          profileComplete: false,
        );
      }
      rethrow;
    }
    if (_client.auth.currentUser?.id != userId) {
      throw const AuthFailure('Your account changed. Please retry.');
    }
    if (response == null) {
      return AppSession(
        userId: userId,
        role: AppRole.worker,
        displayName: 'Finish registration',
        profileComplete: false,
      );
    }
    final profile = Map<String, dynamic>.from(response as Map);

    return AppSession(
      userId: profile['id'] as String,
      role: AppRoleParsing.fromDatabase(profile['role'] as String),
      displayName: profile['full_name'] as String,
      accountStatus: profile['account_status'] as String? ?? 'INACTIVE',
      workerNumber: (profile['worker_number'] as num?)?.toInt(),
    );
  }

  bool _isNoProfileRow(PostgrestException error) {
    final message = error.message.toLowerCase();
    final details = error.details?.toString().toLowerCase() ?? '';
    if (message.contains('"code":"pgrst116"') && message.contains('0 rows')) {
      return true;
    }
    try {
      final decoded = jsonDecode(error.message);
      if (decoded is Map) {
        final code = decoded['code']?.toString();
        final decodedDetails = decoded['details']?.toString().toLowerCase();
        if (code == 'PGRST116' &&
            (decodedDetails?.contains('0 rows') ?? false)) {
          return true;
        }
      }
    } catch (_) {}
    return error.code == 'PGRST116' &&
        (message.contains('0 rows') || details.contains('0 rows'));
  }
}
