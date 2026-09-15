import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/bootstrap.dart';
import '../../events/domain/event_summary.dart';
import '../../performance/domain/performance_review.dart';
import '../domain/attendance_roster.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => SupabaseAttendanceRepository(ref.watch(supabaseClientProvider)),
);

abstract interface class AttendanceRepository {
  Future<List<EventSummary>> loadFieldEvents();

  Future<FieldEventDashboard> loadFieldDashboard();

  Future<List<AttendanceRosterEntry>> loadRoster({
    required String eventId,
    String? searchText,
  });

  Future<void> setAttendance({
    required String assignmentId,
    required AttendanceStatus status,
    String? notes,
  });

  Future<PerformanceReviewResult> recordPerformanceReview(
    PerformanceReviewInput input,
  );

  Future<String?> signedProfilePhotoUrl(String? storagePath);
}

class SupabaseAttendanceRepository implements AttendanceRepository {
  const SupabaseAttendanceRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<EventSummary>> loadFieldEvents() async {
    final response = await _client.rpc('field_event_list');
    return (response as List<dynamic>)
        .map(
          (row) => EventSummary.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<FieldEventDashboard> loadFieldDashboard() async {
    final response = await _client.rpc('field_event_dashboard');
    return FieldEventDashboard.fromJson(
      Map<String, dynamic>.from((response as List).single as Map),
    );
  }

  @override
  Future<List<AttendanceRosterEntry>> loadRoster({
    required String eventId,
    String? searchText,
  }) async {
    final response = await _client.rpc(
      'event_attendance_roster_v2',
      params: {'p_event_id': eventId, 'p_search_text': searchText},
    ).timeout(const Duration(seconds: 20));
    return (response as List<dynamic>)
        .map(
          (row) => AttendanceRosterEntry.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> setAttendance({
    required String assignmentId,
    required AttendanceStatus status,
    String? notes,
  }) {
    return _client.rpc(
      'set_attendance',
      params: {
        'p_assignment_id': assignmentId,
        'p_status': status.databaseValue,
        'p_notes': notes,
      },
    );
  }

  @override
  Future<String?> signedProfilePhotoUrl(String? storagePath) async {
    if (storagePath == null || storagePath.trim().isEmpty) return null;
    return _client.storage
        .from('profile-photos')
        .createSignedUrl(storagePath, 5 * 60);
  }

  @override
  Future<PerformanceReviewResult> recordPerformanceReview(
    PerformanceReviewInput input,
  ) async {
    final response = await _client
        .rpc('record_performance_review', params: input.toRpcParams())
        .single();
    return PerformanceReviewResult.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }
}
