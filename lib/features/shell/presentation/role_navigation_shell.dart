import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_session.dart';
import '../../auth/application/logout.dart';
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
  bool signingOut = false;
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
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: signingOut
                    ? null
                    : () async {
                        setState(() => signingOut = true);
                        try {
                          await logout(ref);
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not sign out. Please retry.',
                                ),
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => signingOut = false);
                        }
                      },
                icon: const Icon(Icons.logout),
                label: Text(signingOut ? 'Signing out…' : 'Sign out'),
              ),
            ),
            NavigationBar(
              selectedIndex: selected < 0 ? 0 : selected,
              onDestinationSelected: signingOut
                  ? null
                  : (index) => context.go(paths[index]),
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  label: 'Home',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.event_outlined),
                  label: 'Events',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.work_outline),
                  label: role == AppRole.worker ? 'My Work' : 'Workers',
                ),
                if (role == AppRole.worker)
                  const NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    label: 'Profile',
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
