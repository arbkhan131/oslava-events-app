enum AppEnvironmentName {
  local,
  development,
  production;

  static AppEnvironmentName parse(String value) {
    switch (value.trim().toLowerCase()) {
      case 'local':
        return AppEnvironmentName.local;
      case 'dev':
      case 'development':
        return AppEnvironmentName.development;
      case 'prod':
      case 'production':
        return AppEnvironmentName.production;
      default:
        throw AppEnvironmentException('Unknown environment "$value".');
    }
  }
}

class AppEnvironment {
  const AppEnvironment({
    required this.name,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  factory AppEnvironment.fromDartDefines() {
    return AppEnvironment.fromValues(
      environment: const String.fromEnvironment(
        'OSLAVA_ENV',
        defaultValue: 'local',
      ),
      supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
      supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
  }

  factory AppEnvironment.fromValues({
    required String environment,
    required String supabaseUrl,
    required String supabaseAnonKey,
  }) {
    final name = AppEnvironmentName.parse(environment);
    final resolvedUrl =
        supabaseUrl.trim().isEmpty && name == AppEnvironmentName.local
        ? 'http://127.0.0.1:54321'
        : supabaseUrl.trim();
    final resolvedAnonKey =
        supabaseAnonKey.trim().isEmpty && name == AppEnvironmentName.local
        ? 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH'
        : supabaseAnonKey.trim();

    final config = AppEnvironment(
      name: name,
      supabaseUrl: resolvedUrl,
      supabaseAnonKey: resolvedAnonKey,
    );

    config.validate();
    return config;
  }

  final AppEnvironmentName name;
  final String supabaseUrl;
  final String supabaseAnonKey;

  bool get isLocal => name == AppEnvironmentName.local;

  void validate() {
    if (supabaseUrl.isEmpty) {
      throw const AppEnvironmentException('SUPABASE_URL is required.');
    }

    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw AppEnvironmentException('Invalid SUPABASE_URL "$supabaseUrl".');
    }

    if (supabaseAnonKey.isEmpty) {
      throw const AppEnvironmentException('SUPABASE_ANON_KEY is required.');
    }

    final lowerKey = supabaseAnonKey.toLowerCase();
    if (lowerKey.contains('service_role') ||
        lowerKey.contains('postgres') ||
        lowerKey.contains('password')) {
      throw const AppEnvironmentException(
        'Only the public Supabase anon key may be bundled.',
      );
    }
  }
}

class AppEnvironmentException implements Exception {
  const AppEnvironmentException(this.message);

  final String message;

  @override
  String toString() => 'AppEnvironmentException: $message';
}
