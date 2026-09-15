import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_session.dart';
import '../../notifications/presentation/alerts_screen.dart';

class RoleNavigationShell extends ConsumerStatefulWidget {
  const RoleNavigationShell({
    required this.role,
    required this.child,
    super.key,
  });
  final AppRole role;
  final Widget child;
  @override
  ConsumerState<RoleNavigationShell> createState() =>
      _RoleNavigationShellState();
}

class _RoleNavigationShellState extends ConsumerState<RoleNavigationShell> {
  @override
  Widget build(BuildContext context) {
    final role = widget.role;
    final paths = [
      role.homePath,
      '${role.homePath}/events',
      if (role == AppRole.worker)
        '/worker/work'
      else
        '${role.homePath}/workers',
      if (role.canUseAdminAi) '${role.homePath}/ai',
      if (role == AppRole.worker) '/worker/profile',
      '${role.homePath}/alerts',
    ];
    final location = GoRouterState.of(context).uri.path;
    final unreadAlerts = ref
        .watch(unreadAlertsProvider)
        .maybeWhen(data: (count) => count, orElse: () => 0);
    final selected = paths.lastIndexWhere(
      (path) =>
          location == path ||
          (path != role.homePath && location.startsWith('$path/')),
    );
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NavigationBar(
              selectedIndex: selected < 0 ? 0 : selected,
              onDestinationSelected: (index) => context.go(paths[index]),
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.event_outlined),
                  selectedIcon: Icon(Icons.event_rounded),
                  label: 'Events',
                ),
                NavigationDestination(
                  icon: Icon(
                    role == AppRole.worker
                        ? Icons.work_outline
                        : Icons.groups_outlined,
                  ),
                  selectedIcon: Icon(
                    role == AppRole.worker
                        ? Icons.work_rounded
                        : Icons.groups_rounded,
                  ),
                  label: role == AppRole.worker ? 'My Work' : 'Workers',
                ),
                if (role == AppRole.worker)
                  const NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: 'Profile',
                  ),
                if (role.canUseAdminAi)
                  const NavigationDestination(
                    icon: Icon(Icons.smart_toy_outlined),
                    selectedIcon: Icon(Icons.smart_toy_rounded),
                    label: 'AI',
                  ),
                NavigationDestination(
                  icon: Badge.count(
                    count: unreadAlerts,
                    isLabelVisible: unreadAlerts > 0,
                    child: const Icon(Icons.notifications_outlined),
                  ),
                  label: 'Alerts',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
