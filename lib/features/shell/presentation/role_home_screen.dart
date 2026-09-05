import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_session.dart';

class RoleHomeScreen extends StatelessWidget {
  const RoleHomeScreen({required this.role, super.key});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Oslava Events')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role.label,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text('Workspace shell ready'),
                const SizedBox(height: 24),
                if (role == AppRole.worker) ...[
                  FilledButton.icon(
                    onPressed: () => context.go('/worker/profile'),
                    icon: const Icon(Icons.person),
                    label: const Text('Profile'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => context.go('/worker/events'),
                    icon: const Icon(Icons.event_available),
                    label: const Text('Events'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => context.go('/worker/work'),
                    icon: const Icon(Icons.work),
                    label: const Text('My Work'),
                  ),
                ],
                if (role.canBrowseWorkers)
                  FilledButton.icon(
                    onPressed: () => context.go('${role.homePath}/workers'),
                    icon: const Icon(Icons.groups),
                    label: const Text('Workers'),
                  ),
                if (role == AppRole.captain || role == AppRole.supervisor) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => context.go('${role.homePath}/events'),
                    icon: const Icon(Icons.fact_check),
                    label: const Text('Events'),
                  ),
                ],
                if (role == AppRole.admin || role == AppRole.superAdmin) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => context.go('${role.homePath}/events'),
                    icon: const Icon(Icons.event),
                    label: const Text('Events'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
