import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/bootstrap.dart';
import '../../booking/domain/booking_application_result.dart';
import '../../booking/domain/waitlist_result.dart';
import '../../booking/domain/worker_assignment.dart';
import '../domain/event_summary.dart';
import '../domain/worker_event.dart';

final eventRepositoryProvider = Provider<EventRepository>(
  (ref) => SupabaseEventRepository(ref.watch(supabaseClientProvider)),
);

abstract interface class EventRepository {
  Future<List<EventSummary>> loadAdminEvents();

  Future<List<WorkerEvent>> loadWorkerEvents();

  Future<WorkerEvent?> loadWorkerEventDetail(String eventId);

  Future<BookingApplicationResult> applyForEvent({
    required String eventId,
    required String idempotencyKey,
    List<String> acknowledgedRequirementIds = const [],
    bool lateCancellationAcknowledged = false,
  });

  Future<WaitlistResult> joinWaitlist({
    required String eventId,
    required String idempotencyKey,
    List<String> acknowledgedRequirementIds = const [],
  });

  Future<List<WorkerAssignment>> loadWorkerAssignments();

  Future<CancellationResult> cancelAssignment({
    required String assignmentId,
    required String reason,
    required String idempotencyKey,
  });

  Future<String> createDraft(EventDraftInput input);

  Future<void> publishEvent(String eventId);

  Future<void> cancelEvent({required String eventId, required String reason});

  Future<void> completeEvent({required String eventId, required String reason});

  Future<void> closeEvent({required String eventId, required String reason});
}

class SupabaseEventRepository implements EventRepository {
  const SupabaseEventRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<EventSummary>> loadAdminEvents() async {
    final response = await _client.rpc('admin_event_list');
    return (response as List<dynamic>)
        .map(
          (row) => EventSummary.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<List<WorkerEvent>> loadWorkerEvents() async {
    final response = await _client.rpc('worker_event_board');
    return (response as List<dynamic>)
        .map(
          (row) => WorkerEvent.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<WorkerEvent?> loadWorkerEventDetail(String eventId) async {
    final response = await _client.rpc(
      'worker_event_detail',
      params: {'p_event_id': eventId},
    );
    final rows = response as List<dynamic>;
    if (rows.isEmpty) {
      return null;
    }
    return WorkerEvent.fromJson(Map<String, dynamic>.from(rows.first as Map));
  }

  @override
  Future<BookingApplicationResult> applyForEvent({
    required String eventId,
    required String idempotencyKey,
    List<String> acknowledgedRequirementIds = const [],
    bool lateCancellationAcknowledged = false,
  }) async {
    final response = await _client.rpc(
      'apply_for_event',
      params: {
        'p_event_id': eventId,
        'p_idempotency_key': idempotencyKey,
        'p_acknowledged_requirement_ids': acknowledgedRequirementIds,
        'p_late_cancellation_acknowledged': lateCancellationAcknowledged,
      },
    );
    final rows = response as List<dynamic>;
    return BookingApplicationResult.fromJson(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  @override
  Future<WaitlistResult> joinWaitlist({
    required String eventId,
    required String idempotencyKey,
    List<String> acknowledgedRequirementIds = const [],
  }) async {
    final response = await _client.rpc(
      'join_waitlist',
      params: {
        'p_event_id': eventId,
        'p_idempotency_key': idempotencyKey,
        'p_acknowledged_requirement_ids': acknowledgedRequirementIds,
      },
    );
    final rows = response as List<dynamic>;
    return WaitlistResult.fromJson(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  @override
  Future<List<WorkerAssignment>> loadWorkerAssignments() async {
    final response = await _client.rpc('worker_my_work');
    return (response as List<dynamic>)
        .map(
          (row) =>
              WorkerAssignment.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<CancellationResult> cancelAssignment({
    required String assignmentId,
    required String reason,
    required String idempotencyKey,
  }) async {
    final response = await _client.rpc(
      'cancel_assignment',
      params: {
        'p_assignment_id': assignmentId,
        'p_reason': reason,
        'p_idempotency_key': idempotencyKey,
      },
    );
    final rows = response as List<dynamic>;
    return CancellationResult.fromJson(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  @override
  Future<String> createDraft(EventDraftInput input) async {
    if (input.tierStrategy == TierStrategy.custom &&
        input.customTierOffsets == null) {
      throw ArgumentError('Custom tier strategy requires release offsets.');
    }

    if (input.customTierOffsets case final offsets? when !offsets.isValid) {
      throw ArgumentError(
        'Tier release offsets must expand in A, B, C, F order.',
      );
    }

    final response = await _client.rpc(
      'create_event_draft',
      params: input.toCreateRpcParams(),
    );
    final eventId = response as String;

    if (input.customTierOffsets case final offsets?) {
      await _client.rpc(
        'configure_event_tier_offsets',
        params: offsets.toConfigureRpcParams(eventId),
      );
    }

    return eventId;
  }

  @override
  Future<void> publishEvent(String eventId) {
    return _client.rpc(
      'publish_event',
      params: {
        'p_event_id': eventId,
        'p_reason': 'Published from admin event detail',
      },
    );
  }

  @override
  Future<void> cancelEvent({required String eventId, required String reason}) {
    return _client.rpc(
      'cancel_event',
      params: {'p_event_id': eventId, 'p_reason': reason},
    );
  }

  @override
  Future<void> completeEvent({
    required String eventId,
    required String reason,
  }) {
    return _client.rpc(
      'complete_event',
      params: {'p_event_id': eventId, 'p_reason': reason},
    );
  }

  @override
  Future<void> closeEvent({required String eventId, required String reason}) {
    return _client.rpc(
      'close_event',
      params: {'p_event_id': eventId, 'p_reason': reason},
    );
  }
}
