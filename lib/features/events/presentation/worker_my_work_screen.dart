import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../booking/domain/worker_assignment.dart';
import '../data/event_repository.dart';

final workerAssignmentsProvider = FutureProvider<List<WorkerAssignment>>(
  (ref) => ref.watch(eventRepositoryProvider).loadWorkerAssignments(),
);

class WorkerMyWorkScreen extends ConsumerWidget {
  const WorkerMyWorkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(workerAssignmentsProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Work'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Confirmed'),
              Tab(text: 'Completed'),
              Tab(text: 'Cancelled'),
            ],
          ),
        ),
        body: SafeArea(
          child: assignments.when(
            data: (items) => TabBarView(
              children: [
                _AssignmentList(
                  items: items
                      .where(
                        (item) => item.status == AssignmentStatus.confirmed,
                      )
                      .toList(),
                  emptyLabel: 'No confirmed work yet',
                ),
                _AssignmentList(
                  items: items
                      .where(
                        (item) => item.status == AssignmentStatus.completed,
                      )
                      .toList(),
                  emptyLabel: 'No completed work yet',
                ),
                _AssignmentList(
                  items: items
                      .where(
                        (item) => item.status == AssignmentStatus.cancelled,
                      )
                      .toList(),
                  emptyLabel: 'No cancelled work yet',
                ),
              ],
            ),
            error: (error, stackTrace) => Center(child: Text(error.toString())),
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
          subtitle: Text('${item.venueName}\n${item.reportingLabel}'),
          isThreeLine: true,
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
      builder: (context) => const _CancelReasonDialog(),
    );
    if (reason == null || reason.trim().isEmpty) {
      return;
    }

    await ref
        .read(eventRepositoryProvider)
        .cancelAssignment(
          assignmentId: assignment.assignmentId,
          reason: reason,
          idempotencyKey:
              'cancel-${DateTime.now().toUtc().microsecondsSinceEpoch}',
        );
    ref.invalidate(workerAssignmentsProvider);
  }
}

class _CancelReasonDialog extends StatefulWidget {
  const _CancelReasonDialog();

  @override
  State<_CancelReasonDialog> createState() => _CancelReasonDialogState();
}

class _CancelReasonDialogState extends State<_CancelReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancel assignment'),
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
          child: const Text('Cancel assignment'),
        ),
      ],
    );
  }
}
