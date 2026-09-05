import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_session.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/password_recovery_screen.dart';
import '../../features/auth/presentation/worker_registration_screen.dart';
import '../../features/events/presentation/admin_event_detail_screen.dart';
import '../../features/events/presentation/admin_event_form_screen.dart';
import '../../features/events/presentation/admin_event_list_screen.dart';
import '../../features/events/presentation/worker_event_detail_screen.dart';
import '../../features/events/presentation/worker_event_list_screen.dart';
import '../../features/events/presentation/worker_my_work_screen.dart';
import '../../features/shell/presentation/role_home_screen.dart';
import '../../features/workers/presentation/edit_worker_profile_screen.dart';
import '../../features/workers/presentation/worker_detail_screen.dart';
import '../../features/workers/presentation/worker_directory_screen.dart';
import '../../features/workers/presentation/worker_profile_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final session =
      ref.watch(authSessionProvider) ?? ref.watch(derivedAuthSessionProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) => roleAwareRedirect(
      isAuthenticated: session != null,
      role: session?.role,
      location: state.uri.path,
    ),
    routes: [
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
        builder: (context, state) =>
            AdminEventDetailScreen(eventId: state.pathParameters['id']!),
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
        builder: (context, state) =>
            AdminEventDetailScreen(eventId: state.pathParameters['id']!),
      ),
    ],
  );
});

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

  if (isLogin || location == '/') {
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
