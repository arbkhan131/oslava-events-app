import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/bootstrap.dart';
import '../../auth/application/auth_session.dart';
import '../domain/worker_profile.dart';

final workerRepositoryProvider = Provider<WorkerRepository>(
  (ref) => SupabaseWorkerRepository(ref.watch(supabaseClientProvider)),
);

abstract interface class WorkerRepository {
  Future<WorkerProfile> loadOwnWorkerProfile();

  Future<void> updateOwnProfile(WorkerProfileUpdate update);

  Future<List<ErasureRequestStatus>> loadMyErasureRequests();

  Future<String> requestMyAccountErasure(String reason);

  Future<void> replaceOwnProfilePhoto({
    required String storagePath,
    required Uint8List bytes,
    required String mimeType,
    String? oldStoragePath,
    required WorkerProfileUpdate currentProfile,
  });

  Future<List<WorkerProfile>> searchWorkers(WorkerDirectoryQuery query);

  Future<List<StaffProfile>> searchStaff({
    String? searchText,
    AppRole? role,
    AccountStatus? accountStatus,
    int limit = 50,
    int offset = 0,
  });

  Future<String?> signedProfilePhotoUrl(String? storagePath);

  Future<String?> signedIdCardUrl(String? storagePath);

  Future<void> reviewWorkerRegistration({
    required String userId,
    required bool approved,
    WorkerCategory? category,
    required String reason,
  });

  Future<String> provisionStaff(StaffProvisionRequest request);

  Future<void> changeUserPhone({
    required String userId,
    required String phoneE164,
    required String reason,
  });

  Future<WorkerProfile> loadWorkerDetail(String userId);

  Future<List<WorkerHistoryEntry>> loadWorkerHistory(String userId);

  Future<void> detainWorker({
    required String userId,
    required String reason,
    String? notes,
  });

  Future<void> releaseWorker({
    required String userId,
    required String reason,
    String? notes,
  });

  Future<WorkerCategoryChangeResult> changeWorkerCategory({
    required String userId,
    required WorkerCategory newCategory,
    required String reason,
    String? notes,
  });
}

class SupabaseWorkerRepository implements WorkerRepository {
  const SupabaseWorkerRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<WorkerProfile> loadOwnWorkerProfile() async {
    final response = await _client
        .rpc(
          'worker_profile_detail',
          params: {'p_target_user_id': _client.auth.currentUser?.id},
        )
        .single();
    return WorkerProfile.fromJson(Map<String, dynamic>.from(response as Map));
  }

  @override
  Future<void> updateOwnProfile(WorkerProfileUpdate update) {
    return _client.rpc('update_own_profile', params: update.toRpcParams());
  }

  @override
  Future<List<ErasureRequestStatus>> loadMyErasureRequests() async {
    final response = await _client.rpc(
      'my_account_erasure_requests',
      params: {'p_limit': 10},
    );
    return (response as List<dynamic>)
        .map(
          (row) => ErasureRequestStatus.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  @override
  Future<String> requestMyAccountErasure(String reason) async {
    final response = await _client.rpc(
      'request_my_account_erasure',
      params: {'p_reason': reason},
    );
    return response as String;
  }

  @override
  Future<void> replaceOwnProfilePhoto({
    required String storagePath,
    required Uint8List bytes,
    required String mimeType,
    String? oldStoragePath,
    required WorkerProfileUpdate currentProfile,
  }) async {
    await _client.storage
        .from('profile-photos')
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );
    await updateOwnProfile(
      WorkerProfileUpdate(
        fullName: currentProfile.fullName,
        initials: currentProfile.initials,
        address: currentProfile.address,
        nativePlace: currentProfile.nativePlace,
        heightCm: currentProfile.heightCm,
        educationStatus: currentProfile.educationStatus,
        hasPreviousExperience: currentProfile.hasPreviousExperience,
        experienceDetails: currentProfile.experienceDetails,
        profilePhotoPath: storagePath,
      ),
    );
    if (oldStoragePath != null && oldStoragePath != storagePath) {
      try {
        await _client.storage.from('profile-photos').remove([oldStoragePath]);
      } catch (_) {
        // Cleanup retry is safe from the edit screen; do not roll back the profile update.
      }
    }
  }

  @override
  Future<List<WorkerProfile>> searchWorkers(WorkerDirectoryQuery query) async {
    final response = await _client.rpc(
      'worker_directory',
      params: {
        'p_search_text': query.searchText,
        'p_account_filter': query.accountStatus?.databaseValue,
        'p_category_filter': query.category?.databaseValue,
        'p_result_limit': query.limit,
        'p_result_offset': query.offset,
      },
    );
    return (response as List<dynamic>)
        .map(
          (row) =>
              WorkerProfile.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<List<StaffProfile>> searchStaff({
    String? searchText,
    AppRole? role,
    AccountStatus? accountStatus,
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _client.rpc(
      'staff_directory',
      params: {
        'p_search_text': searchText,
        'p_role_filter': role?.databaseValue,
        'p_account_filter': accountStatus?.databaseValue,
        'p_result_limit': limit,
        'p_result_offset': offset,
      },
    );
    return (response as List<dynamic>)
        .map(
          (row) => StaffProfile.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<String?> signedProfilePhotoUrl(String? storagePath) async {
    if (storagePath == null || storagePath.trim().isEmpty) return null;
    return _client.storage
        .from('profile-photos')
        .createSignedUrl(storagePath, 5 * 60);
  }

  @override
  Future<String?> signedIdCardUrl(String? storagePath) async {
    if (storagePath == null || storagePath.trim().isEmpty) return null;
    return _client.storage
        .from('worker-id-cards')
        .createSignedUrl(storagePath, 5 * 60);
  }

  @override
  Future<void> reviewWorkerRegistration({
    required String userId,
    required bool approved,
    WorkerCategory? category,
    required String reason,
  }) {
    return _client.rpc(
      'review_worker_registration',
      params: {
        'p_target_user_id': userId,
        'p_approved': approved,
        'p_category': category?.databaseValue,
        'p_reason': reason.trim(),
      },
    );
  }

  @override
  Future<String> provisionStaff(StaffProvisionRequest request) async {
    final response = await _client.functions.invoke(
      'manage-staff-account',
      body: request.toFunctionBody(),
    );
    final data = response.data;
    if (data is Map && data['user_id'] is String) {
      return data['user_id'] as String;
    }
    throw StateError('Staff account was created without a usable response.');
  }

  @override
  Future<void> changeUserPhone({
    required String userId,
    required String phoneE164,
    required String reason,
  }) {
    return _client.rpc(
      'change_user_phone',
      params: {
        'target_user_id': userId,
        'new_phone_e164': phoneE164,
        'reason': reason,
      },
    );
  }

  @override
  Future<WorkerProfile> loadWorkerDetail(String userId) async {
    final response = await _client
        .rpc('worker_profile_detail', params: {'p_target_user_id': userId})
        .single();
    return WorkerProfile.fromJson(Map<String, dynamic>.from(response as Map));
  }

  @override
  Future<List<WorkerHistoryEntry>> loadWorkerHistory(String userId) async {
    final response = await _client.rpc(
      'worker_history',
      params: {'p_target_user_id': userId},
    );
    return (response as List<dynamic>)
        .map(
          (row) => WorkerHistoryEntry.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> detainWorker({
    required String userId,
    required String reason,
    String? notes,
  }) {
    return _changeStatus(
      userId: userId,
      status: AccountStatus.detained,
      reason: reason,
      notes: notes,
    );
  }

  @override
  Future<void> releaseWorker({
    required String userId,
    required String reason,
    String? notes,
  }) {
    return _changeStatus(
      userId: userId,
      status: AccountStatus.active,
      reason: reason,
      notes: notes,
    );
  }

  @override
  Future<WorkerCategoryChangeResult> changeWorkerCategory({
    required String userId,
    required WorkerCategory newCategory,
    required String reason,
    String? notes,
  }) async {
    final response = await _client
        .rpc(
          'change_worker_category',
          params: {
            'p_worker_id': userId,
            'p_new_category': newCategory.databaseValue,
            'p_reason': reason,
            'p_notes': notes,
          },
        )
        .single();
    return WorkerCategoryChangeResult.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<void> _changeStatus({
    required String userId,
    required AccountStatus status,
    required String reason,
    String? notes,
  }) {
    return _client.rpc(
      'change_account_status',
      params: {
        'p_target_user_id': userId,
        'p_new_status': status.databaseValue,
        'p_reason': reason,
        'p_related_event_id': null,
        'p_notes': notes,
      },
    );
  }
}
