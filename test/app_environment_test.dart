import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/core/config/app_environment.dart';

void main() {
  group('AppEnvironment', () {
    test('uses safe local defaults', () {
      final environment = AppEnvironment.fromValues(
        environment: 'local',
        supabaseUrl: '',
        supabaseAnonKey: '',
      );

      expect(environment.name, AppEnvironmentName.local);
      expect(environment.supabaseUrl, 'http://127.0.0.1:54321');
      expect(environment.supabaseAnonKey, 'local-anon-key');
    });

    test('accepts development Supabase configuration', () {
      final environment = AppEnvironment.fromValues(
        environment: 'development',
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'anon.public',
      );

      expect(environment.name, AppEnvironmentName.development);
      expect(environment.supabaseUrl, 'https://example.supabase.co');
      expect(environment.supabaseAnonKey, 'anon.public');
    });

    test('requires development Supabase configuration', () {
      expect(
        () => AppEnvironment.fromValues(
          environment: 'development',
          supabaseUrl: '',
          supabaseAnonKey: '',
        ),
        throwsA(isA<AppEnvironmentException>()),
      );
    });

    test('rejects service-role-like credentials', () {
      expect(
        () => AppEnvironment.fromValues(
          environment: 'development',
          supabaseUrl: 'https://example.supabase.co',
          supabaseAnonKey: 'service_role.secret',
        ),
        throwsA(isA<AppEnvironmentException>()),
      );
    });
  });
}
