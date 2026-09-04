import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_session.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/shell/presentation/role_home_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(authSessionProvider);

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
      for (final role in AppRole.values)
        GoRoute(
          path: role.homePath,
          builder: (context, state) => RoleHomeScreen(role: role),
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

  if (!isAuthenticated) {
    return isLogin ? null : '/login';
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

  return null;
}
