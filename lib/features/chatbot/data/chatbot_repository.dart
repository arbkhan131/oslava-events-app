import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/bootstrap.dart';
import '../../../core/config/app_environment.dart';
import '../domain/chatbot_models.dart';

final chatbotHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final chatbotRepositoryProvider = Provider<ChatbotRepository>((ref) {
  return HttpChatbotRepository(
    ref.watch(appEnvironmentProvider),
    ref.watch(supabaseClientProvider),
    ref.watch(chatbotHttpClientProvider),
  );
});

abstract interface class ChatbotRepository {
  Future<ChatbotAdminProfile> loadMe();
  Future<ChatSessionSummary> createSession();
  Future<List<ChatSessionSummary>> listSessions();
  Future<List<ChatMessageRecord>> loadMessages(
    String sessionId, {
    int limit = 50,
    int offset = 0,
  });
  Future<PendingActionResponse> loadPendingAction(String sessionId);
  Future<ChatTurnResponse> sendMessage({
    required String sessionId,
    required String message,
  });
  Future<ChatTurnResponse> confirmAction(String actionId);
  Future<ChatTurnResponse> cancelAction(String actionId, {String? reason});
}

class HttpChatbotRepository implements ChatbotRepository {
  const HttpChatbotRepository(
    this._environment,
    this._supabase,
    this._httpClient,
  );

  final AppEnvironment _environment;
  final SupabaseClient _supabase;
  final http.Client _httpClient;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(_environment.chatbotBaseUrl);
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      path: [basePath, cleanPath].where((part) => part.isNotEmpty).join('/'),
      queryParameters: query,
    );
  }

  Future<Map<String, String>> _headers() async {
    var session = _supabase.auth.currentSession;
    if (session == null) {
      throw const ChatbotApiException(
        code: 'AUTH_REQUIRED',
        message: 'Sign in to use the AI assistant.',
        retryable: false,
        statusCode: 401,
      );
    }
    if (session.isExpired) {
      final response = await _supabase.auth.refreshSession();
      session = response.session;
    }
    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      throw const ChatbotApiException(
        code: 'AUTH_INVALID',
        message: 'Your session expired.',
        retryable: false,
        statusCode: 401,
      );
    }
    return {
      'authorization': 'Bearer $token',
      'content-type': 'application/json',
      'accept': 'application/json',
    };
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final headers = await _headers();
    final uri = _uri(path, query);
    final encodedBody = body == null ? null : jsonEncode(body);
    final response = await switch (method) {
      'GET' => _httpClient.get(uri, headers: headers),
      'POST' => _httpClient.post(uri, headers: headers, body: encodedBody),
      _ => throw ArgumentError.value(method, 'method'),
    }.timeout(const Duration(seconds: 35));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatbotApiException.fromResponse(
        statusCode: response.statusCode,
        body: response.body,
      );
    }
    if (response.body.trim().isEmpty) return null;
    return jsonDecode(response.body);
  }

  @override
  Future<ChatbotAdminProfile> loadMe() async {
    final response = await _request('GET', '/v1/auth/me');
    return ChatbotAdminProfile.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<ChatSessionSummary> createSession() async {
    final response = await _request('POST', '/v1/chat/sessions');
    return ChatSessionSummary.fromJson(
      Map<String, dynamic>.from(response['session'] as Map),
    );
  }

  @override
  Future<List<ChatSessionSummary>> listSessions() async {
    final response = await _request('GET', '/v1/chat/sessions');
    return (response['sessions'] as List<dynamic>? ?? const [])
        .map(
          (item) => ChatSessionSummary.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<ChatMessageRecord>> loadMessages(
    String sessionId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _request(
      'GET',
      '/v1/chat/sessions/$sessionId/messages',
      query: {'limit': '$limit', 'offset': '$offset'},
    );
    return (response['messages'] as List<dynamic>? ?? const [])
        .map(
          (item) => ChatMessageRecord.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  @override
  Future<PendingActionResponse> loadPendingAction(String sessionId) async {
    final response = await _request(
      'GET',
      '/v1/chat/sessions/$sessionId/action/pending',
    );
    return PendingActionResponse.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<ChatTurnResponse> sendMessage({
    required String sessionId,
    required String message,
  }) async {
    final response = await _request(
      'POST',
      '/v1/chat/sessions/$sessionId/messages',
      body: {'message': message},
    );
    return ChatTurnResponse.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<ChatTurnResponse> confirmAction(String actionId) async {
    final response = await _request(
      'POST',
      '/v1/chat/actions/$actionId/confirm',
    );
    return ChatTurnResponse.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<ChatTurnResponse> cancelAction(
    String actionId, {
    String? reason,
  }) async {
    final body = reason == null || reason.trim().isEmpty
        ? <String, Object?>{}
        : <String, Object?>{'reason': reason.trim()};
    final response = await _request(
      'POST',
      '/v1/chat/actions/$actionId/cancel',
      body: body,
    );
    return ChatTurnResponse.fromJson(Map<String, dynamic>.from(response));
  }
}
