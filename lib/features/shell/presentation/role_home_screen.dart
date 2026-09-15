import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_session.dart';
import '../../auth/presentation/sign_out_button.dart';
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
                const Align(
                  alignment: Alignment.centerRight,
                  child: SignOutButton(),
                ),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF173F7A), Color(0xFF167568)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        role == AppRole.worker
                            ? 'Ready for your next event?'
                            : 'Bring your team together.',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Everything you need for a great event day.',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (role == AppRole.worker) ...[
                  _WorkerHomeSummary(),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Quick access',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _HomeShortcut(
                  icon: Icons.event_available_outlined,
                  title: 'Events',
                  subtitle: role == AppRole.worker
                      ? 'Explore upcoming work and vacancies'
                      : 'Manage events and your event day',
                  onTap: () => context.go('${role.homePath}/events'),
                ),
                if (role == AppRole.worker) ...[
                  _HomeShortcut(
                    icon: Icons.work_outline,
                    title: 'My Work',
                    subtitle: 'Your bookings, waitlist and work history',
                    onTap: () => context.go('/worker/work'),
                  ),
                  _HomeShortcut(
                    icon: Icons.person_outline,
                    title: 'Profile',
                    subtitle: 'Your details, category and performance',
                    onTap: () => context.go('/worker/profile'),
                  ),
                ],
                if (role.canBrowseWorkers)
                  _HomeShortcut(
                    icon: Icons.groups_outlined,
                    title: 'Workers',
                    subtitle: 'Find workers and review their profiles',
                    onTap: () => context.go('${role.homePath}/workers'),
                  ),
                _HomeShortcut(
                  icon: Icons.notifications_outlined,
                  title: 'Alerts',
                  subtitle: 'Stay up to date with your team',
                  onTap: () => context.go('${role.homePath}/alerts'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeShortcut extends StatelessWidget {
  const _HomeShortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
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
        padding: const EdgeInsets.all(20),
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
              Text(
                assignments.isLoading
                    ? 'Loading your work…'
                    : assignments.hasError
                    ? 'Work summary unavailable. Open My Work to retry.'
                    : 'No confirmed work yet.',
              ),
            Text(
              activeWaitlist == null
                  ? 'Waitlist summary unavailable'
                  : 'Active waitlist: ${activeWaitlist.length}',
            ),
            Text(
              events.hasValue
                  ? 'Available events now: $availableCount'
                  : events.hasError
                  ? 'Events unavailable. Open Events to retry.'
                  : 'Loading available events…',
            ),
          ],
        ),
      ),
    );
  }
}
