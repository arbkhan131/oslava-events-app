import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../booking/domain/waitlist_result.dart';
import '../../booking/domain/worker_assignment.dart';
import '../data/event_repository.dart';
import '../domain/event_summary.dart';
import 'worker_event_detail_screen.dart';
import 'worker_event_list_screen.dart';

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
                message: error.toString(),
                onRetry: () => ref.invalidate(workerWaitlistProvider),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => _ErrorState(
              message: error.toString(),
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
      return Center(child: Text(emptyLabel));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          title: Text(item.title),
          subtitle: Text(
            '${item.venueName}\n${item.reportingLabel}\nCancel before ${formatKolkataDateTime12h(item.cancellationDeadlineAt)}',
          ),
          isThreeLine: true,
          onTap: () => context.go('/worker/events/${item.eventId}'),
          trailing: item.canCancel
              ? IconButton(
                  tooltip: 'Cancel assignment',
                  onPressed: () => _cancel(context, ref, item),
                  icon: const Icon(Icons.cancel),
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
            .showSnackBar(SnackBar(content: Text(error.toString())));
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
      return const Center(child: Text('No active waitlist entries'));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          title: Text(item.title),
          subtitle: Text(
            '${item.venueName}\n${item.reportingLabel}\nPosition ${item.queuePosition ?? '-'}',
          ),
          isThreeLine: true,
          onTap: () => context.go('/worker/events/${item.eventId}'),
          trailing: item.canWithdraw
              ? IconButton(
                  tooltip: 'Withdraw waitlist',
                  onPressed: () => _withdraw(context, ref, item),
                  icon: const Icon(Icons.playlist_remove),
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
            .showSnackBar(SnackBar(content: Text(error.toString())));
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
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _reason,
      decoration: const InputDecoration(labelText: 'Reason'),
      autofocus: true,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Back'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_reason.text),
        child: const Text('Save'),
      ),
    ],
  );
}
