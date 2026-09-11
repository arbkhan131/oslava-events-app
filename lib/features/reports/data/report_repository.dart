import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/bootstrap.dart';
import '../domain/event_report.dart';

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => SupabaseReportRepository(ref.watch(supabaseClientProvider)),
);

abstract interface class ReportRepository {
  Future<EventReport> loadEventReport(
    String eventId, {
    String? auditActionFilter,
    String? auditActorRoleFilter,
    int auditLimit = 100,
    int auditOffset = 0,
  });
}

class SupabaseReportRepository implements ReportRepository {
  const SupabaseReportRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<EventReport> loadEventReport(
    String eventId, {
    String? auditActionFilter,
    String? auditActorRoleFilter,
    int auditLimit = 100,
    int auditOffset = 0,
  }) async {
    final summaryResponse = await _client
        .rpc('event_report_summary', params: {'p_event_id': eventId})
        .single();
    final staffingResponse = await _client.rpc(
      'event_staffing_report',
      params: {'p_event_id': eventId},
    );
    final auditResponse = await _client.rpc(
      'event_audit_history_filtered',
      params: {
        'p_event_id': eventId,
        'p_action_filter': auditActionFilter,
        'p_actor_role_filter': auditActorRoleFilter,
        'p_limit': auditLimit,
        'p_offset': auditOffset,
      },
    );

    return EventReport(
      summary: EventReportSummary.fromJson(
        Map<String, dynamic>.from(summaryResponse as Map),
      ),
      staffing: (staffingResponse as List<dynamic>)
          .map(
            (row) => StaffingReportRow.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
      auditHistory: (auditResponse as List<dynamic>)
          .map(
            (row) => EventAuditHistoryRow.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
    );
  }
}
