import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/bootstrap.dart';
import '../../events/domain/event_summary.dart';
import '../domain/attendance_roster.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => SupabaseAttendanceRepository(ref.watch(supabaseClientProvider)),
);

abstract interface class AttendanceRepository {
  Future<List<EventSummary>> loadFieldEvents();

  Future<List<AttendanceRosterEntry>> loadRoster({
    required String eventId,
    String? searchText,
  });

  Future<void> setAttendance({
    required String assignmentId,
    required AttendanceStatus status,
    String? notes,
  });
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
  Future<List<AttendanceRosterEntry>> loadRoster({
    required String eventId,
    String? searchText,
  }) async {
    final response = await _client.rpc(
      'event_attendance_roster',
      params: {'p_event_id': eventId, 'p_search_text': searchText},
    );
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
}
