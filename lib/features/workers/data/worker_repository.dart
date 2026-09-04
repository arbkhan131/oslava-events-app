import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/bootstrap.dart';
import '../domain/worker_profile.dart';

final workerRepositoryProvider = Provider<WorkerRepository>(
  (ref) => SupabaseWorkerRepository(ref.watch(supabaseClientProvider)),
);

abstract interface class WorkerRepository {
  Future<WorkerProfile> loadOwnWorkerProfile();

  Future<void> updateOwnProfile(WorkerProfileUpdate update);

  Future<List<WorkerProfile>> searchWorkers({String? searchText});

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
  Future<List<WorkerProfile>> searchWorkers({String? searchText}) async {
    final response = await _client.rpc(
      'worker_directory',
      params: {
        'p_search_text': searchText,
        'p_account_filter': null,
        'p_category_filter': null,
        'p_result_limit': 50,
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
