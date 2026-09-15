import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/features/chatbot/domain/chatbot_models.dart';

void main() {
  group('Chatbot V1 contract models', () {
    test('parses message response', () {
      final turn = ChatTurnResponse.fromJson({
        'request_id': 'req_1',
        'session_id': 'session-1',
        'message_id': 'message-1',
        'response': {'type': 'message', 'content': 'Today has 2 events.'},
        'session_state': {
          'current_event_id': null,
          'current_event_label': null,
          'current_worker_id': null,
          'current_worker_label': null,
        },
      });

      expect(turn.response.type, ChatbotResponseType.message);
      expect(turn.response.content, 'Today has 2 events.');
    });

    test('parses entity selection response', () {
      final turn = ChatTurnResponse.fromJson({
        'request_id': 'req_2',
        'session_id': 'session-1',
        'message_id': 'message-2',
        'response': {
          'type': 'entity_selection_required',
          'content': 'Which worker?',
          'selection': {
            'entity_type': 'worker',
            'options': [
              {
                'id': 'worker-1',
                'display_name': 'Arif Khan',
                'subtitle': 'Worker #1001 • Category C',
              },
            ],
          },
        },
        'session_state': null,
      });

      expect(turn.response.type, ChatbotResponseType.entitySelectionRequired);
      expect(turn.response.selection!.entityType, 'worker');
      expect(turn.response.selection!.options.single.displayName, 'Arif Khan');
    });

    test('parses confirmation response and friendly pending-action error', () {
      final turn = ChatTurnResponse.fromJson({
        'request_id': 'req_3',
        'session_id': 'session-1',
        'message_id': 'message-3',
        'response': {
          'type': 'confirmation_required',
          'content': 'Please confirm.',
          'action': {
            'id': 'action-1',
            'type': 'change_worker_category',
            'status': 'PENDING',
            'expires_at': '2026-09-14T02:15:00.000Z',
            'summary': {
              'workerName': 'Arif Ahmed',
              'currentCategory': 'B',
              'newCategory': 'A',
            },
          },
        },
        'session_state': {
          'current_event_id': null,
          'current_event_label': null,
          'current_worker_id': 'worker-1',
          'current_worker_label': 'Arif Ahmed',
        },
      });

      expect(turn.response.type, ChatbotResponseType.confirmationRequired);
      expect(turn.response.action!.type, 'change_worker_category');
      expect(turn.sessionState!.currentWorkerLabel, 'Arif Ahmed');
      expect(
        readableChatbotError(
          const ChatbotApiException(
            code: 'PENDING_ACTION_EXISTS',
            message: 'Pending action exists.',
            retryable: false,
            statusCode: 409,
          ),
        ),
        'Please confirm or cancel the pending action first.',
      );
    });

    test('parses pending action response', () {
      final pending = PendingActionResponse.fromJson({
        'request_id': 'req_4',
        'session_id': 'session-1',
        'pending_action': {
          'id': 'action-1',
          'session_id': 'session-1',
          'action_type': 'publish_event',
          'status': 'PENDING',
          'display_summary': {'title': 'VM hall function'},
          'expires_at': '2026-09-14T02:15:00.000Z',
          'created_at': '2026-09-14T02:05:00.000Z',
        },
      });

      expect(pending.pendingAction!.type, 'publish_event');
      expect(pending.pendingAction!.summary['title'], 'VM hall function');
    });

    test('keeps backend request id in internal error message', () {
      final error = ChatbotApiException.fromResponse(
        statusCode: 500,
        body: '{"error":{"code":"INTERNAL_ERROR","message":"An unexpected error occurred.","retryable":false,"request_id":"req_123"}}',
      );

      expect(readableChatbotError(error), contains('server error'));
      expect(readableChatbotError(error), contains('req_123'));
    });
  });
}
