import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ChatbotApiException implements Exception {
  const ChatbotApiException({
    required this.code,
    required this.message,
    required this.retryable,
    required this.statusCode,
    this.requestId,
  });

  final String code;
  final String message;
  final bool retryable;
  final int statusCode;
  final String? requestId;

  static ChatbotApiException fromResponse({
    required int statusCode,
    required String body,
  }) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final error = Map<String, dynamic>.from(decoded['error'] as Map);
        return ChatbotApiException(
          code: error['code']?.toString() ?? 'HTTP_$statusCode',
          message: error['message']?.toString() ?? 'Chatbot request failed.',
          retryable: error['retryable'] == true,
          statusCode: statusCode,
          requestId: error['request_id']?.toString(),
        );
      }
    } catch (_) {}
    return ChatbotApiException(
      code: 'HTTP_$statusCode',
      message: 'Chatbot request failed. Please retry.',
      retryable: statusCode >= 500 || statusCode == 429,
      statusCode: statusCode,
    );
  }

  @override
  String toString() => message;
}

class ChatSessionSummary {
  const ChatSessionSummary({
    required this.id,
    required this.userId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.lastActivityAt,
  });

  final String id;
  final String userId;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastActivityAt;

  factory ChatSessionSummary.fromJson(Map<String, dynamic> json) {
    return ChatSessionSummary(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      lastActivityAt: DateTime.parse(json['last_activity_at'] as String),
    );
  }
}

class ChatMessageRecord {
  const ChatMessageRecord({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final String role;
  final String content;
  final DateTime createdAt;

  factory ChatMessageRecord.fromJson(Map<String, dynamic> json) {
    return ChatMessageRecord(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ChatSessionState {
  const ChatSessionState({
    this.currentEventId,
    this.currentEventLabel,
    this.currentWorkerId,
    this.currentWorkerLabel,
  });

  final String? currentEventId;
  final String? currentEventLabel;
  final String? currentWorkerId;
  final String? currentWorkerLabel;

  factory ChatSessionState.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ChatSessionState();
    return ChatSessionState(
      currentEventId: json['current_event_id'] as String?,
      currentEventLabel: json['current_event_label'] as String?,
      currentWorkerId: json['current_worker_id'] as String?,
      currentWorkerLabel: json['current_worker_label'] as String?,
    );
  }

  bool get hasContext =>
      currentEventLabel != null ||
      currentWorkerLabel != null ||
      currentEventId != null ||
      currentWorkerId != null;
}

class EntitySelectionOption {
  const EntitySelectionOption({
    required this.id,
    required this.displayName,
    required this.subtitle,
  });

  final String id;
  final String displayName;
  final String subtitle;

  factory EntitySelectionOption.fromJson(Map<String, dynamic> json) {
    return EntitySelectionOption(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      subtitle: json['subtitle'] as String,
    );
  }
}

class EntitySelection {
  const EntitySelection({required this.entityType, required this.options});

  final String entityType;
  final List<EntitySelectionOption> options;

  factory EntitySelection.fromJson(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>? ?? const [])
        .map(
          (item) => EntitySelectionOption.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
    return EntitySelection(
      entityType: json['entity_type'] as String,
      options: options,
    );
  }
}

class ChatbotActionSummary {
  const ChatbotActionSummary({
    required this.id,
    required this.type,
    required this.status,
    required this.summary,
    this.expiresAt,
    this.createdAt,
    this.result,
  });

  final String id;
  final String type;
  final String status;
  final Map<String, dynamic> summary;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final Map<String, dynamic>? result;

  factory ChatbotActionSummary.fromTurnJson(Map<String, dynamic> json) {
    return ChatbotActionSummary(
      id: json['id'] as String,
      type: json['type'] as String,
      status: json['status'] as String,
      summary: Map<String, dynamic>.from(json['summary'] as Map? ?? const {}),
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at'] as String),
      result: json['result'] == null
          ? null
          : Map<String, dynamic>.from(json['result'] as Map),
    );
  }

  factory ChatbotActionSummary.fromPendingJson(Map<String, dynamic> json) {
    return ChatbotActionSummary(
      id: json['id'] as String,
      type: json['action_type'] as String,
      status: json['status'] as String,
      summary: Map<String, dynamic>.from(
        json['display_summary'] as Map? ?? const {},
      ),
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at'] as String),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
    );
  }
}

enum ChatbotResponseType {
  message,
  entitySelectionRequired,
  confirmationRequired,
  actionCompleted,
  actionCancelled,
  unknown,
}

class ChatbotResponsePayload {
  const ChatbotResponsePayload({
    required this.type,
    required this.content,
    this.selection,
    this.action,
  });

  final ChatbotResponseType type;
  final String content;
  final EntitySelection? selection;
  final ChatbotActionSummary? action;

  factory ChatbotResponsePayload.fromJson(Map<String, dynamic> json) {
    final rawType = json['type']?.toString() ?? '';
    final type = switch (rawType) {
      'message' => ChatbotResponseType.message,
      'entity_selection_required' =>
        ChatbotResponseType.entitySelectionRequired,
      'confirmation_required' => ChatbotResponseType.confirmationRequired,
      'action_completed' => ChatbotResponseType.actionCompleted,
      'action_cancelled' => ChatbotResponseType.actionCancelled,
      _ => ChatbotResponseType.unknown,
    };
    return ChatbotResponsePayload(
      type: type,
      content: json['content']?.toString() ?? '',
      selection: json['selection'] == null
          ? null
          : EntitySelection.fromJson(
              Map<String, dynamic>.from(json['selection'] as Map),
            ),
      action: json['action'] == null
          ? null
          : ChatbotActionSummary.fromTurnJson(
              Map<String, dynamic>.from(json['action'] as Map),
            ),
    );
  }
}

class ChatTurnResponse {
  const ChatTurnResponse({
    required this.requestId,
    required this.sessionId,
    this.messageId,
    required this.response,
    this.sessionState,
  });

  final String requestId;
  final String sessionId;
  final String? messageId;
  final ChatbotResponsePayload response;
  final ChatSessionState? sessionState;

  factory ChatTurnResponse.fromJson(Map<String, dynamic> json) {
    return ChatTurnResponse(
      requestId: json['request_id'] as String,
      sessionId: json['session_id'] as String,
      messageId: json['message_id'] as String?,
      response: ChatbotResponsePayload.fromJson(
        Map<String, dynamic>.from(json['response'] as Map),
      ),
      sessionState: ChatSessionState.fromJson(
        json['session_state'] == null
            ? null
            : Map<String, dynamic>.from(json['session_state'] as Map),
      ),
    );
  }
}

class PendingActionResponse {
  const PendingActionResponse({required this.requestId, this.pendingAction});

  final String requestId;
  final ChatbotActionSummary? pendingAction;

  factory PendingActionResponse.fromJson(Map<String, dynamic> json) {
    return PendingActionResponse(
      requestId: json['request_id'] as String,
      pendingAction: json['pending_action'] == null
          ? null
          : ChatbotActionSummary.fromPendingJson(
              Map<String, dynamic>.from(json['pending_action'] as Map),
            ),
    );
  }
}

class ChatbotAdminProfile {
  const ChatbotAdminProfile({
    required this.userId,
    required this.role,
    required this.displayName,
    required this.accountStatus,
    this.workerNumber,
  });

  final String userId;
  final String role;
  final String displayName;
  final String accountStatus;
  final int? workerNumber;

  factory ChatbotAdminProfile.fromJson(Map<String, dynamic> json) {
    return ChatbotAdminProfile(
      userId: json['user_id'] as String,
      role: json['role'] as String,
      displayName: json['display_name'] as String,
      accountStatus: json['account_status'] as String,
      workerNumber: json['worker_number'] as int?,
    );
  }
}

String readableChatbotError(Object error) {
  if (error is ChatbotApiException) {
    switch (error.code) {
      case 'AUTH_REQUIRED':
      case 'AUTH_INVALID':
        return 'Your session expired. Sign in again and retry.';
      case 'ROLE_FORBIDDEN':
        return 'The AI assistant is available only for admins.';
      case 'ACCOUNT_RESTRICTED':
        return 'Your admin account is not active.';
      case 'MODEL_RATE_LIMITED':
        return 'The AI server is busy. Please retry shortly.';
      case 'MODEL_TIMEOUT':
        return 'The AI response took too long. Please retry.';
      case 'PENDING_ACTION_EXISTS':
        return 'Please confirm or cancel the pending action first.';
      case 'ACTION_EXPIRED':
        return 'That action expired. Ask the assistant to prepare it again.';
      case 'ACTION_STALE':
        return 'The data changed before confirmation. Ask the assistant to prepare it again.';
      case 'ACTION_ALREADY_RESOLVED':
        return 'That action was already handled.';
      case 'INTERNAL_ERROR':
        return _withRequestId(
          'The AI assistant had a server error. Please share this request ID with the chatbot backend developer.',
          error.requestId,
        );
      default:
        return _withRequestId(error.message, error.requestId);
    }
  }
  if (error is TimeoutException) {
    return 'The AI assistant took too long to respond. Please retry.';
  }
  if (error is SocketException || error is http.ClientException) {
    return 'Could not reach the AI assistant. Check your internet connection and retry.';
  }
  return 'Could not reach the AI assistant. Check your connection and retry.';
}

String _withRequestId(String message, String? requestId) {
  if (requestId == null || requestId.trim().isEmpty) return message;
  return '$message\nRequest ID: $requestId';
}
