import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_session.dart';
import '../../booking/domain/worker_assignment.dart';
import '../../booking/domain/waitlist_result.dart';
import '../../events/domain/worker_event.dart';
import '../../events/presentation/worker_event_list_screen.dart';
import '../../events/presentation/worker_my_work_screen.dart';
import '../../workers/presentation/worker_profile_screen.dart';

class RoleHomeScreen extends ConsumerWidget {
  const RoleHomeScreen({required this.role, super.key});

  final AppRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Oslava Events')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topLeft,
            child: ListView(
              children: [
                Text(
                  role.label,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text('Choose a section below or use the navigation bar.'),
                if (role == AppRole.admin || role == AppRole.superAdmin)
                  const Text(
                    'Team management and full reports will become available in the upcoming phases.',
                  ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.go('${role.homePath}/alerts'),
                  icon: const Icon(Icons.notifications),
                  label: const Text('Alerts'),
                ),
                const SizedBox(height: 8),
                if (role == AppRole.worker) ...[
                  _WorkerHomeSummary(),
                  const SizedBox(height: 12),
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

class _WorkerHomeSummary extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(workerAssignmentsProvider);
    final waitlist = ref.watch(workerWaitlistProvider);
    final profile = ref.watch(ownWorkerProfileProvider);
    final events = ref.watch(workerEventsProvider);
    final nextWork = assignments.maybeWhen<List<WorkerAssignment>?>(
      data: (items) {
        final confirmed = items
            .where((item) => item.status == AssignmentStatus.confirmed)
            .toList();
        confirmed.sort((a, b) => a.reportingAt.compareTo(b.reportingAt));
        return confirmed;
      },
      orElse: () => null,
    );
    final activeWaitlist = waitlist.maybeWhen<List<WorkerWaitlistEntry>?>(
      data: (items) => items
          .where((item) => item.status == WaitlistEntryStatus.waiting)
          .toList(),
      orElse: () => null,
    );
    final availableCount = events.maybeWhen<int>(
      data: (items) => items
          .where((item) => item.actionState == WorkerEventActionState.available)
          .length,
      orElse: () => 0,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today for you',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              profile.when(
                data: (worker) =>
                    'Category ${worker.category?.databaseValue ?? 'not assigned'} · ${worker.reliabilityState.label(worker.reliabilitySampleCount)}',
                error: (_, _) =>
                    'Profile summary unavailable. Pull to retry from Profile.',
                loading: () => 'Loading profile…',
              ),
            ),
            const SizedBox(height: 8),
            if (nextWork != null && nextWork.isNotEmpty)
              Text(
                'Next work: ${nextWork.first.title} at ${nextWork.first.reportingLabel}',
              )
            else
              const Text('No confirmed work yet.'),
            Text('Active waitlist: ${activeWaitlist?.length ?? 0}'),
            Text('Available events now: $availableCount'),
          ],
        ),
      ),
    );
  }
}
