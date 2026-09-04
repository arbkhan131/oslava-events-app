import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/app/app.dart';
import 'package:oslava_events/app/bootstrap.dart';
import 'package:oslava_events/core/config/app_environment.dart';

void main() {
  testWidgets('boots to Login with local configuration', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authBootstrapEnabledProvider.overrideWithValue(false),
          appEnvironmentProvider.overrideWithValue(
            AppEnvironment.fromValues(
              environment: 'local',
              supabaseUrl: '',
              supabaseAnonKey: '',
            ),
          ),
        ],
        child: const OslavaApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Oslava Events'), findsWidgets);
  });

  testWidgets('boots to Login with development configuration', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authBootstrapEnabledProvider.overrideWithValue(false),
          appEnvironmentProvider.overrideWithValue(
            AppEnvironment.fromValues(
              environment: 'development',
              supabaseUrl: 'https://example.supabase.co',
              supabaseAnonKey: 'anon.public',
            ),
          ),
        ],
        child: const OslavaApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
  });
}
