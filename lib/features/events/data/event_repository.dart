import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/bootstrap.dart';
import '../domain/event_summary.dart';

final eventRepositoryProvider = Provider<EventRepository>(
  (ref) => SupabaseEventRepository(ref.watch(supabaseClientProvider)),
);

abstract interface class EventRepository {
  Future<List<EventSummary>> loadAdminEvents();

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
