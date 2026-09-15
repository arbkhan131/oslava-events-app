import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oslava_events/features/events/data/event_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'friend worker search sends normalized phone query to Supabase',
    () async {
      Map<String, dynamic>? params;
      final client = SupabaseClient(
        'https://events.example.test',
        'public-test-key',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/search_bookable_friend_workers')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            params = Map<String, dynamic>.from(body['params'] as Map? ?? body);
            return http.Response(
              jsonEncode([
                {
                  'worker_id': 'worker-id',
                  'worker_number': 12,
                  'full_name': 'Friend Worker',
                  'phone_e164': '+919012768298',
                  'category': 'F',
                  'tier_eligible': true,
                },
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response(
            jsonEncode({}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
        authOptions: const AuthClientOptions(
          autoRefreshToken: false,
          authFlowType: AuthFlowType.implicit,
        ),
      );
      addTearDown(client.dispose);

      final results = await SupabaseEventRepository(client)
          .searchBookableFriendWorkers(
            phoneQuery: '9012768298',
            eventId: '00000000-0000-0000-0000-000000000001',
          );

      expect(params?['p_phone_query'], '+919012768298');
      expect(results.single.phoneE164, '+919012768298');
    },
  );
}
