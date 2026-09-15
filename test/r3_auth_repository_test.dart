import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:oslava_events/features/auth/data/auth_repository.dart';
import 'package:oslava_events/features/auth/data/profile_photo_preparer.dart';
import 'package:oslava_events/features/auth/domain/auth_failure.dart';
import 'package:oslava_events/features/auth/domain/email_address.dart';
import 'package:oslava_events/features/auth/domain/phone_number.dart';
import 'package:oslava_events/features/auth/domain/worker_registration_input.dart';

const uid = '00000000-0000-0000-0000-000000093001';
const hiddenEmail = '919876543210@phone.oslava.local';
WorkerRegistrationInput input({DateTime? dob}) => WorkerRegistrationInput(
  registrationType: WorkerRegistrationType.newWorker,
  fullName: 'Test Worker',
  phone: PhoneNumber.parse('+919876543210'),
  password: 'test-password',
  profilePhotoPath: 'pending',
  idCardFilePath: 'pending-id',
  dateOfBirth: dob ?? DateTime(1990),
  place: 'Town',
  heightCm: 170,
  educationStatus: 'College',
  experienceLevel: WorkerExperienceLevel.noExperience,
  privacyTermsVersion: 'server-v2',
);
Uint8List photo() =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: 4, height: 4)));
Uint8List idCard() => Uint8List.fromList(utf8.encode('pdf bytes'));

class AuthServer {
  int phoneAccountCreates = 0, profilePhotoUploads = 0, idCardUploads = 0;
  bool failCompletion = false, failPassword = false;
  Map<String, dynamic> metadata = {};
  Map<String, dynamic>? profile;
  final requests = <http.Request>[];
  Map<String, dynamic> get user => {
    'id': uid,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': hiddenEmail,
    'phone': null,
    'created_at': '2026-01-01T00:00:00Z',
    'app_metadata': {},
    'user_metadata': metadata,
  };
  Map<String, dynamic> get session {
    String encode(Object data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    final token =
        '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': uid, 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.test';
    return {
      'access_token': token,
      'refresh_token': 'test-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': user,
    };
  }

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    Object? body = {};
    var status = 200;
    if (path.endsWith('/functions/v1/create-worker-phone-account')) {
      phoneAccountCreates++;
      final payload = jsonDecode(request.body) as Map;
      expect(payload['phone'], '+919876543210');
      expect(payload['password'], 'test-password');
      body = {'user_id': uid, 'phone_e164': '+919876543210'};
    } else if (path.endsWith('/token')) {
      final payload = jsonDecode(request.body) as Map;
      expect(payload['email'] ?? payload['username'], hiddenEmail);
      body = session;
    } else if (path.endsWith('/user')) {
      if (request.method == 'PUT') {
        final payload = jsonDecode(request.body) as Map;
        if (failPassword && payload.containsKey('password')) {
          return http.Response(
            jsonEncode({'code': 'weak_password', 'msg': 'Rejected'}),
            400,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        metadata.addAll(
          Map<String, dynamic>.from(payload['data'] as Map? ?? {}),
        );
      }
      body = user;
    } else if (path.contains('/storage/v1/object/profile-photos/')) {
      profilePhotoUploads++;
      body = {'Key': 'profile-photos/$uid/profile.jpg'};
    } else if (path.contains('/storage/v1/object/worker-id-cards/')) {
      idCardUploads++;
      body = {'Key': 'worker-id-cards/$uid/id.pdf'};
    } else if (path.endsWith('/my_profile')) {
      if (profile == null) {
        return http.Response(
          jsonEncode({
            'code': 'PGRST116',
            'details': 'The result contains 0 rows',
            'hint': null,
            'message': 'Cannot coerce the result to a single JSON object',
          }),
          406,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      body = profile;
    } else if (path.endsWith('/complete_phone_worker_registration')) {
      if (failCompletion) {
        status = 400;
        body = {'code': 'TEST_ERROR', 'message': 'Interrupted completion'};
      } else {
        final payload = jsonDecode(request.body) as Map;
        final params = payload['params'] as Map? ?? payload;
        expect(params['phone_e164'], '+919876543210');
        expect(params['registration_type'], 'NEW_WORKER');
        expect(params['p_requested_category'], isNull);
        expect(params['experience_level'], 'NO_EXPERIENCE');
        profile = {
          'id': uid,
          'role': 'WORKER',
          'full_name': 'Test Worker',
          'account_status': 'PENDING_APPROVAL',
          'worker_number': 93001,
        };
        body = [
          {
            'user_id': uid,
            'worker_number': 93001,
            'role': 'WORKER',
            'category': 'F',
            'requested_category': null,
            'account_status': 'PENDING_APPROVAL',
          },
        ];
      }
    } else if (path.endsWith('/privacy_terms_versions')) {
      body = {
        'version': 'server-v2',
        'summary': 'Readable server policy',
        'published_at': '2026-01-01',
      };
    } else if (path.endsWith('/logout')) {
      status = 204;
      body = null;
    }
    return http.Response(
      status == 204 ? '' : jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

void main() {
  late AuthServer server;
  late SupabaseClient client;
  late SupabaseAuthRepository repository;
  setUp(() {
    server = AuthServer();
    client = SupabaseClient(
      'https://auth.example.test',
      'public-test-key',
      httpClient: MockClient(server.handle),
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    repository = SupabaseAuthRepository(client, const ProfilePhotoPreparer());
  });
  tearDown(() async {
    await client.dispose();
  });
  test('invalid photo fails before an Auth identity is created', () async {
    await expectLater(
      repository.registerWorker(
        input: input(),
        profilePhotoBytes: Uint8List.fromList([1, 2]),
        profilePhotoMimeType: 'image/jpeg',
        idCardBytes: idCard(),
        idCardFileName: 'id.pdf',
        idCardMimeType: 'application/pdf',
      ),
      throwsFormatException,
    );
    expect(server.phoneAccountCreates, 0);
  });
  test('underage input fails before Auth account creation', () async {
    await expectLater(
      repository.registerWorker(
        input: input(dob: DateTime.now()),
        profilePhotoBytes: photo(),
        profilePhotoMimeType: 'image/jpeg',
        idCardBytes: idCard(),
        idCardFileName: 'id.pdf',
        idCardMimeType: 'application/pdf',
      ),
      throwsFormatException,
    );
    expect(server.phoneAccountCreates, 0);
  });
  test('successful phone registration returns pending server Worker ID and saves no password in draft', () async {
    final result = await repository.registerWorker(
      input: input(),
      profilePhotoBytes: photo(),
      profilePhotoMimeType: 'image/jpeg',
      idCardBytes: idCard(),
      idCardFileName: 'id.pdf',
      idCardMimeType: 'application/pdf',
    );
    expect(result.workerNumber, 93001);
    expect(result.accountStatus, 'PENDING_APPROVAL');
    expect(result.isRestricted, true);
    expect(jsonEncode(server.metadata), isNot(contains('test-password')));
    expect(server.phoneAccountCreates, 1);
    expect(server.profilePhotoUploads, 1);
    expect(server.idCardUploads, 1);
  });
  test(
    'interrupted completion reuses Auth account and uploaded files',
    () async {
      server.failCompletion = true;
      await expectLater(
        repository.registerWorker(
          input: input(),
          profilePhotoBytes: photo(),
          profilePhotoMimeType: 'image/jpeg',
          idCardBytes: idCard(),
          idCardFileName: 'id.pdf',
          idCardMimeType: 'application/pdf',
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect((await repository.loadCurrentSession())!.profileComplete, false);
      server.failCompletion = false;
      final result = await repository.registerWorker(
        input: input(),
        profilePhotoBytes: Uint8List(0),
        profilePhotoMimeType: 'image/jpeg',
        idCardBytes: idCard(),
        idCardFileName: 'id.pdf',
        idCardMimeType: 'application/pdf',
      );
      expect(result.workerNumber, 93001);
      expect(server.phoneAccountCreates, 1);
      expect(server.profilePhotoUploads, 1);
      expect(server.idCardUploads, 2);
    },
  );
  test('OTP registration is disabled', () async {
    await expectLater(
      repository.verifyRegistrationOtp('123456'),
      throwsA(isA<AuthFailure>()),
    );
    await expectLater(
      repository.resendRegistrationOtp(),
      throwsA(isA<AuthFailure>()),
    );
  });
  test(
    'recovery sends password reset email for legacy staff recovery only',
    () async {
      await repository.startPasswordRecovery(
        email: EmailAddress.parse('worker@example.test'),
        environmentName: 'staging',
      );
      final recover = jsonDecode(
        server.requests.firstWhere((r) => r.url.path.endsWith('/recover')).body,
      ) as Map;
      expect(recover['email'], 'worker@example.test');
    },
  );
  test('in-app password update is not used for email recovery', () async {
    await expectLater(
      repository.verifyRecoveryOtpAndSetPassword(
        email: EmailAddress.parse('worker@example.test'),
        otp: '123456',
        newPassword: 'new-password',
      ),
      throwsA(isA<AuthFailure>()),
    );
  });
  test('terms version and readable content come from the server', () async {
    final terms = await repository.loadPrivacyTerms();
    expect(terms['version'], 'server-v2');
    expect(terms['summary'], 'Readable server policy');
  });
}
