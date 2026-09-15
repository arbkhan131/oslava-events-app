import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/bootstrap.dart';
import '../../booking/domain/booking_application_result.dart';
import '../../booking/domain/friend_booking.dart';
import '../../booking/domain/waitlist_result.dart';
import '../../booking/domain/worker_assignment.dart';
import '../domain/event_summary.dart';
import '../domain/worker_event.dart';

final eventRepositoryProvider = Provider<EventRepository>(
  (ref) => SupabaseEventRepository(ref.watch(supabaseClientProvider)),
);

abstract interface class EventRepository {
  Future<List<EventSummary>> loadAdminEvents();

  Future<AdminEventDashboard> loadAdminDashboard();

  Future<AdminEventDetail> loadAdminEventDetail(String eventId);

  Future<List<WorkerEvent>> loadWorkerEvents();

  Future<WorkerEvent?> loadWorkerEventDetail(String eventId);

  Future<BookingApplicationResult> applyForEvent({
    required String eventId,
    required String idempotencyKey,
    List<String> acknowledgedRequirementIds = const [],
    bool lateCancellationAcknowledged = false,
  });

  Future<BookingApplicationResult> getBookingResult(String requestId);

  Future<List<FriendWorker>> searchBookableFriendWorkers({
    required String phoneQuery,
    required String eventId,
  });

  Future<FriendBookingResult> applyForEventWithFriend({
    required String eventId,
    required String friendWorkerId,
    required String idempotencyKey,
    List<String> acknowledgedRequirementIds = const [],
    bool lateCancellationAcknowledged = false,
  });

  Future<BookingApplicationResult?> loadPendingBooking(String eventId);

  Future<WaitlistResult> joinWaitlist({
    required String eventId,
    required String idempotencyKey,
    List<String> acknowledgedRequirementIds = const [],
  });

  Future<List<WorkerAssignment>> loadWorkerAssignments();

  Future<List<WorkerWaitlistEntry>> loadWorkerWaitlist();

  Future<WaitlistEntryStatus> withdrawWaitlist({
    required String waitlistEntryId,
    required String reason,
  });

  Future<CancellationResult> cancelAssignment({
    required String assignmentId,
    required String reason,
    required String idempotencyKey,
  });

  Future<String> createDraft(EventDraftInput input);

  Future<int> updateEvent({
    required String eventId,
    required int expectedVersion,
    required EventDraftInput input,
    required String reason,
    bool confirmConflicts = false,
  });

  Future<void> publishEvent(String eventId);

  Future<void> cancelEvent({required String eventId, required String reason});

  Future<void> completeEvent({required String eventId, required String reason});

  Future<void> closeEvent({required String eventId, required String reason});
}

class SupabaseEventRepository implements EventRepository {
  const SupabaseEventRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<BookingApplicationResult> getBookingResult(String requestId) async {
    final response = await _client.rpc(
      'get_booking_result',
      params: {'p_booking_request_id': requestId},
    );
    return BookingApplicationResult.fromJson(
      Map<String, dynamic>.from((response as List).single as Map),
    );
  }

  @override
  Future<List<FriendWorker>> searchBookableFriendWorkers({
    required String phoneQuery,
    required String eventId,
  }) async {
    final response = await _client.rpc(
      'search_bookable_friend_workers',
      params: {
        'p_phone_query': _normalizePhoneSearchQuery(phoneQuery),
        'p_event_id': eventId,
        'p_limit': 10,
      },
    );
    return (response as List<dynamic>)
        .map(
          (row) => FriendWorker.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  String _normalizePhoneSearchQuery(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) return '+91$digits';
    if (digits.length == 12 && digits.startsWith('91')) return '+$digits';
    return input.trim();
  }

  @override
  Future<FriendBookingResult> applyForEventWithFriend({
    required String eventId,
    required String friendWorkerId,
    required String idempotencyKey,
    List<String> acknowledgedRequirementIds = const [],
    bool lateCancellationAcknowledged = false,
  }) async {
    final response = await _client.rpc(
      'apply_for_event_with_friend',
      params: {
        'p_event_id': eventId,
        'p_friend_worker_id': friendWorkerId,
        'p_idempotency_key': idempotencyKey,
        'p_acknowledged_requirement_ids': acknowledgedRequirementIds,
        'p_late_cancellation_acknowledged': lateCancellationAcknowledged,
      },
    );
    final rows = response as List<dynamic>;
    return FriendBookingResult.fromJson(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  @override
  Future<BookingApplicationResult?> loadPendingBooking(String eventId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client
        .from('booking_requests')
        .select('id')
        .eq('worker_id', userId)
        .eq('event_id', eventId)
        .eq('result', 'PENDING')
        .maybeSingle();
    if (row == null) return null;
    return getBookingResult(row['id'] as String);
  }

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
  Future<AdminEventDashboard> loadAdminDashboard() async {
    final response = await _client.rpc('admin_event_dashboard');
    return AdminEventDashboard.fromJson(
      Map<String, dynamic>.from((response as List).single as Map),
    );
  }

  @override
  Future<AdminEventDetail> loadAdminEventDetail(String eventId) async {
    final response = await _client.rpc(
      'admin_event_detail',
      params: {'p_event_id': eventId},
    );
    return AdminEventDetail.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
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
      'worker_event_detail_full',
      params: {'p_event_id': eventId},
    );
    if (response == null) return null;
    return WorkerEvent.fromJson(Map<String, dynamic>.from(response as Map));
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
  Future<List<WorkerWaitlistEntry>> loadWorkerWaitlist() async {
    final response = await _client.rpc('worker_my_waitlist');
    return (response as List<dynamic>)
        .map(
          (row) => WorkerWaitlistEntry.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  @override
  Future<WaitlistEntryStatus> withdrawWaitlist({
    required String waitlistEntryId,
    required String reason,
  }) async {
    final response = await _client.rpc(
      'withdraw_waitlist',
      params: {'p_waitlist_entry_id': waitlistEntryId, 'p_reason': reason},
    );
    return WaitlistEntryStatus.fromDatabase(response as String);
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
  Future<int> updateEvent({
    required String eventId,
    required int expectedVersion,
    required EventDraftInput input,
    required String reason,
    bool confirmConflicts = false,
  }) async {
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
      'update_event',
      params: input.toUpdateRpcParams(
        eventId: eventId,
        expectedVersion: expectedVersion,
        reason: reason,
        confirmConflicts: confirmConflicts,
      ),
    );
    return (response as num).toInt();
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
