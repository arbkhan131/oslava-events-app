import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oslava_events/core/config/app_environment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('local Supabase seeded role accounts sign in on Android', (
    tester,
  ) async {
    final environment = AppEnvironment.fromDartDefines();
    final client = _LocalSupabaseClient(
      baseUrl: environment.supabaseUrl,
      publishableKey: environment.supabaseAnonKey,
    );

    for (final account in _accounts) {
      final token = await client.signIn(
        phone: account.phone,
        password: account.password,
      );
      final profile = await client.myProfile(token);

      expect(profile['role'], account.databaseRole, reason: account.label);
      expect(profile['account_status'], 'ACTIVE', reason: account.label);
      expect(profile['category'], account.category, reason: account.label);
    }
  });
}

const _accounts = [
  _LocalAccount(
    label: 'Super Admin',
    phone: '+919000000001',
    password: 'OslavaDev!01',
    databaseRole: 'SUPER_ADMIN',
  ),
  _LocalAccount(
    label: 'Admin',
    phone: '+919000000002',
    password: 'OslavaDev!02',
    databaseRole: 'ADMIN',
  ),
  _LocalAccount(
    label: 'Captain',
    phone: '+919000000003',
    password: 'OslavaDev!03',
    databaseRole: 'CAPTAIN',
  ),
  _LocalAccount(
    label: 'Supervisor',
    phone: '+919000000004',
    password: 'OslavaDev!04',
    databaseRole: 'SUPERVISOR',
  ),
  _LocalAccount(
    label: 'Worker F',
    phone: '+919000000005',
    password: 'OslavaDev!05',
    databaseRole: 'WORKER',
    category: 'F',
  ),
  _LocalAccount(
    label: 'Worker C',
    phone: '+919000000006',
    password: 'OslavaDev!06',
    databaseRole: 'WORKER',
    category: 'C',
  ),
  _LocalAccount(
    label: 'Worker B',
    phone: '+919000000007',
    password: 'OslavaDev!07',
    databaseRole: 'WORKER',
    category: 'B',
  ),
  _LocalAccount(
    label: 'Worker A',
    phone: '+919000000008',
    password: 'OslavaDev!08',
    databaseRole: 'WORKER',
    category: 'A',
  ),
];

class _LocalAccount {
  const _LocalAccount({
    required this.label,
    required this.phone,
    required this.password,
    required this.databaseRole,
    this.category,
  });

  final String label;
  final String phone;
  final String password;
  final String databaseRole;
  final String? category;
}

class _LocalSupabaseClient {
  const _LocalSupabaseClient({
    required this.baseUrl,
    required this.publishableKey,
  });

  final String baseUrl;
  final String publishableKey;

  Future<String> signIn({
    required String phone,
    required String password,
  }) async {
    final response = await _post(
      '$baseUrl/auth/v1/token?grant_type=password',
      headers: {'apikey': publishableKey},
      body: {'phone': phone, 'password': password},
    );

    return response['access_token'] as String;
  }

  Future<Map<String, dynamic>> myProfile(String accessToken) async {
    final response = await _post(
      '$baseUrl/rest/v1/rpc/my_profile',
      headers: {'apikey': publishableKey, 'Authorization': 'Bearer $accessToken'},
      body: <String, dynamic>{},
    );

    if (response is List<dynamic>) {
      return Map<String, dynamic>.from(response.single as Map);
    }

    return Map<String, dynamic>.from(response as Map);
  }

  Future<dynamic> _post(
    String url, {
    required Map<String, String> headers,
    required Map<String, dynamic> body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.contentType = ContentType.json;
      for (final header in headers.entries) {
        request.headers.set(header.key, header.value);
      }
      request.write(jsonEncode(body));

      final response = await request.close();
      final text = await utf8.decodeStream(response);
      final decoded = text.isEmpty ? null : jsonDecode(text);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        fail('POST $url failed with ${response.statusCode}: $decoded');
      }

      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}
