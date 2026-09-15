import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../booking/domain/waitlist_result.dart';
import '../../booking/domain/worker_assignment.dart';
import '../data/event_repository.dart';
import '../domain/event_summary.dart';
import 'worker_event_detail_screen.dart';
import 'worker_event_list_screen.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../auth/presentation/auth_widgets.dart';

final workerAssignmentsProvider = FutureProvider<List<WorkerAssignment>>(
  (ref) => ref.watch(eventRepositoryProvider).loadWorkerAssignments(),
);

final workerWaitlistProvider = FutureProvider<List<WorkerWaitlistEntry>>(
  (ref) => ref.watch(eventRepositoryProvider).loadWorkerWaitlist(),
);

class WorkerMyWorkScreen extends ConsumerWidget {
  const WorkerMyWorkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(workerAssignmentsProvider);
    final waitlist = ref.watch(workerWaitlistProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Work'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: () {
                ref.invalidate(workerAssignmentsProvider);
                ref.invalidate(workerWaitlistProvider);
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Confirmed'),
              Tab(text: 'Waitlist'),
              Tab(text: 'Completed'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: SafeArea(
          child: assignments.when(
            data: (assignmentItems) => waitlist.when(
              data: (waitlistItems) => TabBarView(
                children: [
                  _AssignmentList(
                    items: assignmentItems
                        .where(
                          (item) => item.status == AssignmentStatus.confirmed,
                        )
                        .toList(),
                    emptyLabel: 'No confirmed work yet',
                  ),
                  _WaitlistList(
                    items: waitlistItems
                        .where(
                          (item) => item.status == WaitlistEntryStatus.waiting,
                        )
                        .toList(),
                  ),
                  _AssignmentList(
                    items: assignmentItems
                        .where(
                          (item) => item.status == AssignmentStatus.completed,
                        )
                        .toList(),
                    emptyLabel: 'No completed work yet',
                  ),
                  _HistoryList(
                    assignments: assignmentItems
                        .where(
                          (item) =>
                              item.status != AssignmentStatus.confirmed &&
                              item.status != AssignmentStatus.completed,
                        )
                        .toList(),
                    waitlist: waitlistItems
                        .where(
                          (item) => item.status != WaitlistEntryStatus.waiting,
                        )
                        .toList(),
                  ),
                ],
              ),
              error: (error, _) => _ErrorState(
                message: 'Couldn’t load your waitlist. Please try again.',
                onRetry: () => ref.invalidate(workerWaitlistProvider),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => _ErrorState(
              message: 'Couldn’t load your work. Please try again.',
              onRetry: () => ref.invalidate(workerAssignmentsProvider),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
    );
  }
}

class _AssignmentList extends ConsumerWidget {
  const _AssignmentList({required this.items, required this.emptyLabel});

  final List<WorkerAssignment> items;
  final String emptyLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return ListView(
        children: [
          AppEmptyState(
            icon: Icons.work_outline_rounded,
            title: emptyLabel,
            message: 'Explore upcoming events to find your next opportunity.',
            action: OutlinedButton(
              onPressed: () => context.go('/worker/events'),
              child: const Text('Explore events'),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final item = items[index];
        return _WorkCard(
          title: item.title,
          venue: item.venueName,
          reporting: item.reportingLabel,
          status: item.status == AssignmentStatus.completed
              ? 'Completed'
              : 'Confirmed',
          detail: item.status == AssignmentStatus.completed
              ? 'This event is in your work history.'
              : 'Cancellation deadline: ${formatKolkataDateTime12h(item.cancellationDeadlineAt)}',
          onOpen: () => context.go('/worker/events/${item.eventId}'),
          secondaryAction: item.canCancel
              ? TextButton.icon(
                  onPressed: () => _cancel(context, ref, item),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel assignment'),
                )
              : null,
        );
      },
    );
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    WorkerAssignment assignment,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ReasonDialog(title: 'Cancel assignment'),
    );
    if (reason == null || reason.trim().isEmpty) return;
    try {
      final result = await ref
          .read(eventRepositoryProvider)
          .cancelAssignment(
            assignmentId: assignment.assignmentId,
            reason: reason.trim(),
            idempotencyKey:
                'cancel-${DateTime.now().toUtc().microsecondsSinceEpoch}',
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Assignment ${result.status.name}.')),
      );
      ref.invalidate(workerAssignmentsProvider);
      ref.invalidate(workerWaitlistProvider);
      ref.invalidate(workerEventsProvider);
      ref.invalidate(workerEventDetailProvider(assignment.eventId));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyAuthError(error))));
      }
    }
  }
}

class _WaitlistList extends ConsumerWidget {
  const _WaitlistList({required this.items});
  final List<WorkerWaitlistEntry> items;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return ListView(
        children: const [
          AppEmptyState(
            icon: Icons.hourglass_empty_rounded,
            title: 'No active waitlist entries',
            message: 'When you join a full event’s waitlist, your position will appear here.',
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final item = items[index];
        return _WorkCard(
          title: item.title,
          venue: item.venueName,
          reporting: item.reportingLabel,
          status: 'Waitlist',
          detail: 'Queue position: ${item.queuePosition ?? 'Pending'}',
          onOpen: () => context.go('/worker/events/${item.eventId}'),
          secondaryAction: item.canWithdraw
              ? TextButton.icon(
                  onPressed: () => _withdraw(context, ref, item),
                  icon: const Icon(Icons.playlist_remove),
                  label: const Text('Withdraw waitlist'),
                )
              : null,
        );
      },
    );
  }

  Future<void> _withdraw(
    BuildContext context,
    WidgetRef ref,
    WorkerWaitlistEntry entry,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ReasonDialog(title: 'Withdraw waitlist'),
    );
    if (reason == null || reason.trim().isEmpty) return;
    try {
      final status = await ref
          .read(eventRepositoryProvider)
          .withdrawWaitlist(
            waitlistEntryId: entry.waitlistEntryId,
            reason: reason.trim(),
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Waitlist ${status.name}.')));
      ref.invalidate(workerWaitlistProvider);
      ref.invalidate(workerEventsProvider);
      ref.invalidate(workerEventDetailProvider(entry.eventId));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyAuthError(error))));
      }
    }
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.assignments, required this.waitlist});
  final List<WorkerAssignment> assignments;
  final List<WorkerWaitlistEntry> waitlist;
  @override
  Widget build(BuildContext context) {
    if (assignments.isEmpty && waitlist.isEmpty) {
      return const Center(
        child: Text('No cancelled, removed or waitlist history yet'),
      );
    }
    return ListView(
      children: [
        for (final item in assignments)
          ListTile(
            title: Text(item.title),
            subtitle: Text('${item.venueName}\n${item.reportingLabel}'),
            trailing: Text(item.status.name),
            onTap: () => context.go('/worker/events/${item.eventId}'),
          ),
        for (final item in waitlist)
          ListTile(
            title: Text(item.title),
            subtitle: Text('${item.venueName}\n${item.reportingLabel}'),
            trailing: Text(item.status.name),
            onTap: () => context.go('/worker/events/${item.eventId}'),
          ),
      ],
    );
  }
}

class _WorkCard extends StatelessWidget {
  const _WorkCard({
    required this.title,
    required this.venue,
    required this.reporting,
    required this.status,
    required this.detail,
    required this.onOpen,
    this.secondaryAction,
  });
  final String title, venue, reporting, status, detail;
  final VoidCallback onOpen;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Chip(
            avatar: Icon(
              status == 'Completed'
                  ? Icons.task_alt
                  : status == 'Waitlist'
                  ? Icons.hourglass_empty
                  : Icons.event_available,
              size: 18,
            ),
            label: Text(status),
          ),
          const SizedBox(height: 8),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(venue),
          const SizedBox(height: 8),
          Text(
            'Reporting · $reporting',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Divider(height: 28),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('View event'),
              ),
              ?secondaryAction,
            ],
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title});
  final String title;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will release your place. Review your decision before continuing.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              minLines: 2,
              maxLines: 4,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a reason to continue.'
                  : null,
              autofocus: true,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Back'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.of(context).pop(_reason.text);
          }
        },
        child: const Text('Confirm'),
      ),
    ],
  );
}
