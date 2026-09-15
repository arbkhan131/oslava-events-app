import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/app/app.dart';
import 'package:oslava_events/app/bootstrap.dart';
import 'package:oslava_events/app/router/app_router.dart';
import 'package:oslava_events/core/config/app_environment.dart';
import 'package:oslava_events/features/auth/application/auth_session.dart';

void main() {
  group('roleAwareRedirect', () {
    test('sends unauthenticated users to Login', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: false,
          role: null,
          location: '/worker',
        ),
        '/login',
      );
    });

    test('allows unauthenticated users to open registration and recovery', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: false,
          role: null,
          location: '/register',
        ),
        isNull,
      );
      expect(
        roleAwareRedirect(
          isAuthenticated: false,
          role: null,
          location: '/recovery',
        ),
        isNull,
      );
    });

    test('sends authenticated workers to the worker shell', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.worker,
          location: '/login',
        ),
        '/worker',
      );
    });

    test('prevents authenticated users from opening another role shell', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.admin,
          location: '/worker',
        ),
        '/admin',
      );
    });

    test('allows Admin and Super Admin to open the AI assistant', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.admin,
          location: '/admin/ai',
        ),
        isNull,
      );
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.superAdmin,
          location: '/super-admin/ai',
        ),
        isNull,
      );
    });

    test('prevents non-admin roles from opening the AI assistant', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.worker,
          location: '/admin/ai',
        ),
        '/worker',
      );
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.captain,
          location: '/super-admin/ai',
        ),
        '/captain',
      );
    });
  });

  for (final role in AppRole.values) {
    testWidgets('${role.label} reaches the correct empty shell', (
      tester,
    ) async {
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
            authSessionProvider.overrideWith(
              (ref) => AppSession(
                userId: 'test-user',
                role: role,
                displayName: 'Test User',
              ),
            ),
          ],
          child: const OslavaApp(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text(role.label), findsOneWidget);
      expect(
        find.text(
          role == AppRole.worker
              ? 'Ready for your next event?'
              : 'Bring your team together.',
        ),
        findsOneWidget,
      );
      expect(find.text('Sign out'), findsOneWidget);
    });
  }
}
