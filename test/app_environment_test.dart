import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/core/config/app_environment.dart';

void main() {
  group('AppEnvironment', () {
    test('uses safe local defaults for Android via adb reverse', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final environment = AppEnvironment.fromValues(
        environment: 'local',
        supabaseUrl: '',
        supabaseAnonKey: '',
      );

      expect(environment.name, AppEnvironmentName.local);
      expect(environment.supabaseUrl, 'http://127.0.0.1:55321');
      expect(
        environment.supabaseAnonKey,
        'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
      );
      expect(environment.chatbotBaseUrl, 'https://oslava-chatbot.vercel.app');
      debugDefaultTargetPlatformOverride = null;
    });

    test('uses safe local defaults for non-Android platforms', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final environment = AppEnvironment.fromValues(
        environment: 'local',
        supabaseUrl: '',
        supabaseAnonKey: '',
      );

      expect(environment.name, AppEnvironmentName.local);
      expect(environment.supabaseUrl, 'http://127.0.0.1:55321');
      debugDefaultTargetPlatformOverride = null;
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

    test('accepts staging Supabase configuration', () {
      final environment = AppEnvironment.fromValues(
        environment: 'staging',
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'anon.public',
      );

      expect(environment.name, AppEnvironmentName.staging);
      expect(environment.supabaseUrl, 'https://example.supabase.co');
      expect(environment.supabaseAnonKey, 'anon.public');
      expect(environment.chatbotBaseUrl, 'https://oslava-chatbot.vercel.app');
    });

    test('accepts chatbot base URL override', () {
      final environment = AppEnvironment.fromValues(
        environment: 'staging',
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'anon.public',
        chatbotBaseUrl: 'https://chatbot.example.com',
      );

      expect(environment.chatbotBaseUrl, 'https://chatbot.example.com');
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

    test('rejects invalid chatbot base URL', () {
      expect(
        () => AppEnvironment.fromValues(
          environment: 'development',
          supabaseUrl: 'https://example.supabase.co',
          supabaseAnonKey: 'anon.public',
          chatbotBaseUrl: 'not a url',
        ),
        throwsA(isA<AppEnvironmentException>()),
      );
    });
  });
}
