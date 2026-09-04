import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../../../features/auth/application/auth_session.dart';
import '../data/worker_repository.dart';
import '../domain/worker_profile.dart';

final workerSearchTextProvider = StateProvider<String>((ref) => '');

final workerDirectoryProvider = FutureProvider<List<WorkerProfile>>((ref) {
  final searchText = ref.watch(workerSearchTextProvider);
  return ref
      .watch(workerRepositoryProvider)
      .searchWorkers(searchText: searchText.trim().isEmpty ? null : searchText);
});

class WorkerDirectoryScreen extends ConsumerWidget {
  const WorkerDirectoryScreen({required this.role, super.key});

  final AppRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workers = ref.watch(workerDirectoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Workers')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Search workers',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) =>
                    ref.read(workerSearchTextProvider.notifier).state = value,
              ),
            ),
            Expanded(
              child: workers.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const Center(child: Text('No workers found'));
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final worker = items[index];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(worker.fullName),
                        subtitle: Text(
                          'ID ${worker.workerNumber ?? '-'}  ${worker.category?.databaseValue ?? 'No category'}  ${worker.accountStatus.databaseValue}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go(
                          '${role.homePath}/workers/${worker.userId}',
                        ),
                      );
                    },
                  );
                },
                error: (error, stackTrace) =>
                    Center(child: Text(error.toString())),
                loading: () => const Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
