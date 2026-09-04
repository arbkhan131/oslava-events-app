import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_session.dart';
import '../data/worker_repository.dart';
import '../domain/worker_profile.dart';
import 'worker_directory_screen.dart';

final workerDetailProvider = FutureProvider.family<WorkerProfile, String>((
  ref,
  userId,
) {
  return ref.watch(workerRepositoryProvider).loadWorkerDetail(userId);
});

final workerHistoryProvider =
    FutureProvider.family<List<WorkerHistoryEntry>, String>((ref, userId) {
      return ref.watch(workerRepositoryProvider).loadWorkerHistory(userId);
    });

class WorkerDetailScreen extends ConsumerWidget {
  const WorkerDetailScreen({
    required this.userId,
    required this.viewerRole,
    super.key,
  });

  final String userId;
  final AppRole viewerRole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(workerDetailProvider(userId));
    final history = ref.watch(workerHistoryProvider(userId));

    return Scaffold(
      appBar: AppBar(title: const Text('Worker detail')),
      body: SafeArea(
        child: detail.when(
          data: (worker) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                worker.fullName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('Worker ID ${worker.workerNumber ?? '-'}'),
              Text('Phone ${worker.phoneE164}'),
              Text('Category ${worker.category?.databaseValue ?? 'None'}'),
              Text('Account ${worker.accountStatus.databaseValue}'),
              if (viewerRole.canDetainWorkers) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: worker.accountStatus == AccountStatus.detained
                          ? null
                          : () => _changeStatus(context, ref, worker, true),
                      icon: const Icon(Icons.block),
                      label: const Text('Detain'),
                    ),
                    OutlinedButton.icon(
                      onPressed: worker.accountStatus == AccountStatus.active
                          ? null
                          : () => _changeStatus(context, ref, worker, false),
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Release'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Text('History', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              history.when(
                data: (entries) {
                  if (entries.isEmpty) {
                    return const Text('No history yet');
                  }
                  return Column(
                    children: [
                      for (final entry in entries)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${entry.historyType}: ${entry.action}'),
                          subtitle: Text(
                            '${entry.oldValue ?? '-'} -> ${entry.newValue ?? '-'}\n${entry.reason}',
                          ),
                        ),
                    ],
                  );
                },
                error: (error, stackTrace) => Text(error.toString()),
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
            ],
          ),
          error: (error, stackTrace) => Center(child: Text(error.toString())),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    WorkerProfile worker,
    bool detain,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ReasonDialog(),
    );
    if (reason == null || reason.trim().isEmpty) {
      return;
    }

    final repository = ref.read(workerRepositoryProvider);
    if (detain) {
      await repository.detainWorker(userId: worker.userId, reason: reason);
    } else {
      await repository.releaseWorker(userId: worker.userId, reason: reason);
    }

    ref.invalidate(workerDetailProvider(worker.userId));
    ref.invalidate(workerHistoryProvider(worker.userId));
    ref.invalidate(workerDirectoryProvider);
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reason required'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(labelText: 'Reason'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
