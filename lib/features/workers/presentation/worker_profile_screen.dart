import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/worker_repository.dart';
import '../domain/worker_profile.dart';

final ownWorkerProfileProvider = FutureProvider<WorkerProfile>(
  (ref) => ref.watch(workerRepositoryProvider).loadOwnWorkerProfile(),
);

class WorkerProfileScreen extends ConsumerWidget {
  const WorkerProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(ownWorkerProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: profile.when(
          data: (worker) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _WorkerHeader(worker: worker),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.go('/worker/profile/edit'),
                icon: const Icon(Icons.edit),
                label: const Text('Edit profile'),
              ),
              const SizedBox(height: 16),
              _InfoRow(label: 'Phone', value: worker.phoneE164),
              _InfoRow(
                label: 'Category',
                value: worker.category?.databaseValue ?? 'None',
              ),
              _InfoRow(
                label: 'Account',
                value: worker.accountStatus.databaseValue,
              ),
              _InfoRow(
                label: 'Address',
                value: worker.address ?? 'Not available',
              ),
              _InfoRow(
                label: 'Native place',
                value: worker.nativePlace ?? 'Not available',
              ),
              _InfoRow(
                label: 'Education',
                value: worker.educationStatus ?? 'Not available',
              ),
            ],
          ),
          error: (error, stackTrace) => Center(child: Text(error.toString())),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

class _WorkerHeader extends StatelessWidget {
  const _WorkerHeader({required this.worker});

  final WorkerProfile worker;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(worker.fullName, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Worker ID ${worker.workerNumber ?? '-'}'),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
