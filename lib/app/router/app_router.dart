import '../app.dart' show authBootstrapEnabledProvider;
import '../../features/auth/presentation/session_status_screen.dart';
import '../../features/shell/presentation/role_navigation_shell.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_session.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/password_recovery_screen.dart';
import '../../features/auth/presentation/worker_registration_screen.dart';
import '../../features/attendance/presentation/attendance_roster_screen.dart';
import '../../features/attendance/presentation/field_event_list_screen.dart';
import '../../features/events/presentation/admin_event_detail_screen.dart';
import '../../features/events/presentation/admin_event_form_screen.dart';
import '../../features/events/presentation/admin_event_list_screen.dart';
import '../../features/events/presentation/worker_event_detail_screen.dart';
import '../../features/events/presentation/worker_event_list_screen.dart';
import '../../features/events/presentation/worker_my_work_screen.dart';
import '../../features/notifications/presentation/alerts_screen.dart';
import '../../features/reports/presentation/event_report_screen.dart';
import '../../features/shell/presentation/role_home_screen.dart';
import '../../features/workers/presentation/edit_worker_profile_screen.dart';
import '../../features/workers/presentation/worker_detail_screen.dart';
import '../../features/workers/presentation/worker_directory_screen.dart';
import '../../features/workers/presentation/worker_profile_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final controller = ref.read(authSessionControllerProvider);
  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: controller,
    redirect: (context, state) {
      final session = ref.read(authSessionProvider) ?? controller.session;
      if (ref.read(authBootstrapEnabledProvider) &&
          ref.read(authSessionProvider) == null) {
        if (controller.authFlowInProgress) return null;
        if (controller.loading ||
            controller.error != null ||
            session?.isRestricted == true) {
          return state.uri.path == '/session' ? null : '/session';
        }
        if (session != null && !session.profileComplete) {
          return state.uri.path == '/register' ? null : '/register';
        }
      }
      if (state.uri.path == '/session') {
        return session?.role.homePath ?? '/login';
      }
      return roleAwareRedirect(
        isAuthenticated: session != null,
        role: session?.role,
        location: state.uri.path,
      );
    },
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page unavailable')),
      body: Center(
        child: TextButton(
          onPressed: () => context.go('/'),
          child: const Text('Return home'),
        ),
      ),
    ),
    routes: _nestRoleRoutes([
      GoRoute(
        path: '/session',
        builder: (context, state) => const SessionStatusScreen(),
      ),

      GoRoute(path: '/', builder: (context, state) => const SizedBox.shrink()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const WorkerRegistrationScreen(),
      ),
      GoRoute(
        path: '/recovery',
        builder: (context, state) => const PasswordRecoveryScreen(),
      ),
      for (final role in AppRole.values)
        GoRoute(
          path: role.homePath,
          builder: (context, state) => RoleHomeScreen(role: role),
        ),
      for (final role in AppRole.values)
        GoRoute(
          path: '${role.homePath}/alerts',
          builder: (context, state) => const AlertsScreen(),
        ),
      GoRoute(
        path: '/worker/profile',
        builder: (context, state) => const WorkerProfileScreen(),
      ),
      GoRoute(
        path: '/worker/profile/edit',
        builder: (context, state) => const EditWorkerProfileScreen(),
      ),
      GoRoute(
        path: '/worker/events',
        builder: (context, state) => const WorkerEventListScreen(),
      ),
      GoRoute(
        path: '/worker/events/:id',
        builder: (context, state) =>
            WorkerEventDetailScreen(eventId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/worker/work',
        builder: (context, state) => const WorkerMyWorkScreen(),
      ),
      GoRoute(
        path: '/captain/events',
        builder: (context, state) =>
            const FieldEventListScreen(basePath: '/captain'),
      ),
      GoRoute(
        path: '/captain/events/:id',
        builder: (context, state) => AttendanceRosterScreen(
          eventId: state.pathParameters['id']!,
          basePath: '/captain',
        ),
      ),
      GoRoute(
        path: '/captain/events/:id/report',
        builder: (context, state) =>
            EventReportScreen(eventId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/captain/workers',
        builder: (context, state) =>
            const WorkerDirectoryScreen(role: AppRole.captain),
      ),
      GoRoute(
        path: '/captain/workers/:id',
        builder: (context, state) => WorkerDetailScreen(
          userId: state.pathParameters['id']!,
          viewerRole: AppRole.captain,
        ),
      ),
      GoRoute(
        path: '/supervisor/events',
        builder: (context, state) =>
            const FieldEventListScreen(basePath: '/supervisor'),
      ),
      GoRoute(
        path: '/supervisor/events/:id',
        builder: (context, state) => AttendanceRosterScreen(
          eventId: state.pathParameters['id']!,
          basePath: '/supervisor',
        ),
      ),
      GoRoute(
        path: '/supervisor/events/:id/report',
        builder: (context, state) =>
            EventReportScreen(eventId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/supervisor/workers',
        builder: (context, state) =>
            const WorkerDirectoryScreen(role: AppRole.supervisor),
      ),
      GoRoute(
        path: '/supervisor/workers/:id',
        builder: (context, state) => WorkerDetailScreen(
          userId: state.pathParameters['id']!,
          viewerRole: AppRole.supervisor,
        ),
      ),
      GoRoute(
        path: '/admin/workers',
        builder: (context, state) =>
            const WorkerDirectoryScreen(role: AppRole.admin),
      ),
      GoRoute(
        path: '/admin/workers/:id',
        builder: (context, state) => WorkerDetailScreen(
          userId: state.pathParameters['id']!,
          viewerRole: AppRole.admin,
        ),
      ),
      GoRoute(
        path: '/admin/events',
        builder: (context, state) =>
            const AdminEventListScreen(basePath: '/admin'),
      ),
      GoRoute(
        path: '/admin/events/new',
        builder: (context, state) =>
            const AdminEventFormScreen(basePath: '/admin'),
      ),
      GoRoute(
        path: '/admin/events/:id',
        builder: (context, state) => AdminEventDetailScreen(
          eventId: state.pathParameters['id']!,
          basePath: '/admin',
        ),
      ),
      GoRoute(
        path: '/admin/events/:id/edit',
        builder: (context, state) => AdminEventFormScreen(
          basePath: '/admin',
          eventId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/admin/events/:id/attendance',
        builder: (context, state) => AttendanceRosterScreen(
          eventId: state.pathParameters['id']!,
          basePath: '/admin',
        ),
      ),
      GoRoute(
        path: '/admin/events/:id/report',
        builder: (context, state) =>
            EventReportScreen(eventId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/super-admin/workers',
        builder: (context, state) =>
            const WorkerDirectoryScreen(role: AppRole.superAdmin),
      ),
      GoRoute(
        path: '/super-admin/workers/:id',
        builder: (context, state) => WorkerDetailScreen(
          userId: state.pathParameters['id']!,
          viewerRole: AppRole.superAdmin,
        ),
      ),
      GoRoute(
        path: '/super-admin/events',
        builder: (context, state) =>
            const AdminEventListScreen(basePath: '/super-admin'),
      ),
      GoRoute(
        path: '/super-admin/events/new',
        builder: (context, state) =>
            const AdminEventFormScreen(basePath: '/super-admin'),
      ),
      GoRoute(
        path: '/super-admin/events/:id',
        builder: (context, state) => AdminEventDetailScreen(
          eventId: state.pathParameters['id']!,
          basePath: '/super-admin',
        ),
      ),
      GoRoute(
        path: '/super-admin/events/:id/edit',
        builder: (context, state) => AdminEventFormScreen(
          basePath: '/super-admin',
          eventId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/super-admin/events/:id/attendance',
        builder: (context, state) => AttendanceRosterScreen(
          eventId: state.pathParameters['id']!,
          basePath: '/super-admin',
        ),
      ),
      GoRoute(
        path: '/super-admin/events/:id/report',
        builder: (context, state) =>
            EventReportScreen(eventId: state.pathParameters['id']!),
      ),
    ]),
  );
  ref.onDispose(router.dispose);
  return router;
});

List<RouteBase> _nestRoleRoutes(List<GoRoute> flat) {
  GoRoute nested(GoRoute parent, String fullPath, String relativePath) {
    final descendants = flat
        .where((route) => route.path.startsWith('$fullPath/'))
        .toList();
    final direct = descendants.where(
      (route) => !descendants.any(
        (other) => other != route && route.path.startsWith('${other.path}/'),
      ),
    );
    return GoRoute(
      path: relativePath,
      builder: parent.builder,
      routes: direct
          .map(
            (child) => nested(
              child,
              child.path,
              child.path.substring(fullPath.length + 1),
            ),
          )
          .toList(),
    );
  }

  return [
    ...flat.where(
      (route) => !AppRole.values.any(
        (role) =>
            route.path == role.homePath ||
            route.path.startsWith('${role.homePath}/'),
      ),
    ),
    for (final role in AppRole.values)
      ShellRoute(
        builder: (context, state, child) => Consumer(
          builder: (context, ref, _) {
            final session =
                ref.watch(authSessionProvider) ??
                ref.watch(derivedAuthSessionProvider);
            return RoleNavigationShell(
              key: ValueKey(
                '${session?.userId}:${session?.role}:${session?.accountStatus}',
              ),
              role: role,
              child: child,
            );
          },
        ),
        routes: [
          nested(
            flat.firstWhere((route) => route.path == role.homePath),
            role.homePath,
            role.homePath,
          ),
        ],
      ),
  ];
}

String? roleAwareRedirect({
  required bool isAuthenticated,
  required AppRole? role,
  required String location,
}) {
  final isLogin = location == '/login';
  final isPublicAuthRoute =
      location == '/login' ||
      location == '/register' ||
      location == '/recovery';

  if (!isAuthenticated) {
    return isPublicAuthRoute ? null : '/login';
  }

  final homePath = role?.homePath;
  if (homePath == null) {
    return '/login';
  }

  if (isPublicAuthRoute || isLogin || location == '/') {
    return homePath;
  }

  final routeIsRoleHome = AppRole.values.any(
    (knownRole) => knownRole.homePath == location,
  );

  if (routeIsRoleHome && location != homePath) {
    return homePath;
  }

  if (location.startsWith('/worker/') && role != AppRole.worker) {
    return homePath;
  }

  if (location.startsWith('/captain/') && role != AppRole.captain) {
    return homePath;
  }

  if (location.startsWith('/supervisor/') && role != AppRole.supervisor) {
    return homePath;
  }

  if (location.startsWith('/admin/') && role != AppRole.admin) {
    return homePath;
  }

  if (location.startsWith('/super-admin/') && role != AppRole.superAdmin) {
    return homePath;
  }

  return null;
}

void invalidateUserData(WidgetRef ref) {
  ref.invalidate(adminEventsProvider);
  ref.invalidate(workerEventsProvider);
  ref.invalidate(workerEventDetailProvider);
  ref.invalidate(workerAssignmentsProvider);
  ref.invalidate(fieldEventsProvider);
  ref.invalidate(attendanceRosterProvider);
  ref.invalidate(ownWorkerProfileProvider);
  ref.invalidate(workerDetailProvider);
  ref.invalidate(workerHistoryProvider);
  ref.invalidate(workerDirectoryProvider);
  ref.invalidate(workerSearchTextProvider);
  ref.invalidate(eventReportProvider);
  ref.invalidate(alertsProvider);
}
