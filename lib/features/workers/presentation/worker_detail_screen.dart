import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
              _ProfileAvatar(path: worker.profilePhotoPath),
              const SizedBox(height: 8),
              Text('Worker ID ${worker.workerNumber ?? '-'}'),
              Text('Phone ${worker.phoneE164}'),
              Text('Category ${worker.category?.databaseValue ?? 'None'}'),
              Text('Account ${worker.accountStatus.label}'),
              const SizedBox(height: 12),
              _RegistrationSummary(worker: worker),
              if (worker.accountStatus == AccountStatus.pendingApproval &&
                  viewerRole.canChangeWorkerCategory) ...[
                const SizedBox(height: 16),
                _RegistrationReviewActions(worker: worker),
              ],
              const SizedBox(height: 12),
              _ReliabilitySummary(worker: worker),
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
                    OutlinedButton.icon(
                      onPressed: () => _changePhone(context, ref, worker),
                      icon: const Icon(Icons.phone),
                      label: const Text('Change phone'),
                    ),
                  ],
                ),
              ],
              if (viewerRole.canChangeWorkerCategory &&
                  worker.role == AppRole.worker &&
                  worker.accountStatus == AccountStatus.active &&
                  worker.category != null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _changeCategory(context, ref, worker),
                  icon: const Icon(Icons.trending_up),
                  label: const Text('Change category'),
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

  Future<void> _changePhone(
    BuildContext context,
    WidgetRef ref,
    WorkerProfile worker,
  ) async {
    final request = await showDialog<_PhoneChangeRequest>(
      context: context,
      builder: (context) => const _PhoneChangeDialog(),
    );
    if (request == null || request.reason.trim().isEmpty) return;
    try {
      await ref
          .read(workerRepositoryProvider)
          .changeUserPhone(
            userId: worker.userId,
            phoneE164: request.phoneE164,
            reason: request.reason,
          );
      ref.invalidate(workerDetailProvider(worker.userId));
      ref.invalidate(workerHistoryProvider(worker.userId));
      ref.invalidate(workerDirectoryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Phone updated')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
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

  Future<void> _changeCategory(
    BuildContext context,
    WidgetRef ref,
    WorkerProfile worker,
  ) async {
    final currentCategory = worker.category;
    if (currentCategory == null) {
      return;
    }

    final request = await showDialog<_CategoryChangeRequest>(
      context: context,
      builder: (context) => _CategoryChangeDialog(
        currentCategory: currentCategory,
        options: currentCategory.oneStepOptions,
      ),
    );
    if (request == null || request.reason.trim().isEmpty) {
      return;
    }

    try {
      await ref
          .read(workerRepositoryProvider)
          .changeWorkerCategory(
            userId: worker.userId,
            newCategory: request.newCategory,
            reason: request.reason,
          );
      ref.invalidate(workerDetailProvider(worker.userId));
      ref.invalidate(workerHistoryProvider(worker.userId));
      ref.invalidate(workerDirectoryProvider);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Category updated')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _RegistrationSummary extends ConsumerWidget {
  const _RegistrationSummary({required this.worker});

  final WorkerProfile worker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dob = worker.dateOfBirth;
    final age = worker.completeYearsOld();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Registration',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _DetailLine(label: 'Type', value: worker.registrationTypeLabel),
            _DetailLine(
              label: 'Requested category',
              value: worker.requestedCategory?.label ?? '-',
            ),
            _DetailLine(label: 'Place', value: worker.nativePlace ?? '-'),
            _DetailLine(
              label: 'Date of birth',
              value: dob == null
                  ? '-'
                  : '${dob.toIso8601String().split('T').first} (${age ?? '-'} years)',
            ),
            _DetailLine(
              label: 'Height',
              value: worker.heightCm == null
                  ? '-'
                  : '${worker.heightCm!.toStringAsFixed(0)} cm',
            ),
            _DetailLine(
              label: 'Studying class',
              value: worker.educationStatus ?? '-',
            ),
            _DetailLine(
              label: 'Experience',
              value: worker.experienceLevelLabel,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: worker.idCardFilePath == null
                  ? null
                  : () => _openIdCard(context, ref),
              icon: const Icon(Icons.badge_outlined),
              label: const Text('Open ID card'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openIdCard(BuildContext context, WidgetRef ref) async {
    try {
      final url = await ref
          .read(workerRepositoryProvider)
          .signedIdCardUrl(worker.idCardFilePath);
      if (url == null) throw StateError('ID card file is unavailable.');
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open ID card')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _RegistrationReviewActions extends ConsumerWidget {
  const _RegistrationReviewActions({required this.worker});

  final WorkerProfile worker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pending approval',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Approve only after checking the worker details and ID card.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _approve(context, ref),
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Approve worker'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _reject(context, ref),
                  icon: const Icon(Icons.cancel),
                  label: const Text('Reject'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final request = await showDialog<_ApprovalRequest>(
      context: context,
      builder: (context) => _ApprovalDialog(worker: worker),
    );
    if (request == null || !context.mounted) return;
    await _review(
      context,
      ref,
      approved: true,
      category: request.category,
      reason: request.reason,
      successMessage: 'Worker approved',
    );
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ReasonDialog(title: 'Reject registration'),
    );
    if (reason == null || reason.trim().isEmpty || !context.mounted) return;
    await _review(
      context,
      ref,
      approved: false,
      category: null,
      reason: reason,
      successMessage: 'Registration rejected',
    );
  }

  Future<void> _review(
    BuildContext context,
    WidgetRef ref, {
    required bool approved,
    required WorkerCategory? category,
    required String reason,
    required String successMessage,
  }) async {
    try {
      await ref
          .read(workerRepositoryProvider)
          .reviewWorkerRegistration(
            userId: worker.userId,
            approved: approved,
            category: category,
            reason: reason,
          );
      ref.invalidate(workerDetailProvider(worker.userId));
      ref.invalidate(workerHistoryProvider(worker.userId));
      ref.invalidate(workerDirectoryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _ApprovalRequest {
  const _ApprovalRequest({required this.category, required this.reason});

  final WorkerCategory category;
  final String reason;
}

class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog({required this.worker});

  final WorkerProfile worker;

  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  late WorkerCategory _category =
      widget.worker.requestedCategory ??
      widget.worker.category ??
      WorkerCategory.f;
  final _reason = TextEditingController(text: 'Registration approved');

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Approve registration'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<WorkerCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Approved category'),
            items: [
              for (final category in WorkerCategory.values)
                DropdownMenuItem(value: category, child: Text(category.label)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _category = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Reason'),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_reason.text.trim().isEmpty) return;
            Navigator.of(context).pop(
              _ApprovalRequest(
                category: _category,
                reason: _reason.text.trim(),
              ),
            );
          },
          child: const Text('Approve'),
        ),
      ],
    );
  }
}

class _ProfileAvatar extends ConsumerWidget {
  const _ProfileAvatar({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String?>(
      future: ref.read(workerRepositoryProvider).signedProfilePhotoUrl(path),
      builder: (context, snapshot) {
        final url = snapshot.data;
        return Align(
          alignment: Alignment.centerLeft,
          child: CircleAvatar(
            radius: 36,
            backgroundImage: url == null ? null : NetworkImage(url),
            child: url == null ? const Icon(Icons.person) : null,
          ),
        );
      },
    );
  }
}

class _PhoneChangeRequest {
  const _PhoneChangeRequest({required this.phoneE164, required this.reason});

  final String phoneE164;
  final String reason;
}

class _PhoneChangeDialog extends StatefulWidget {
  const _PhoneChangeDialog();

  @override
  State<_PhoneChangeDialog> createState() => _PhoneChangeDialogState();
}

class _PhoneChangeDialogState extends State<_PhoneChangeDialog> {
  final _phone = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change phone'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'New phone'),
          ),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _PhoneChangeRequest(
              phoneE164: _phone.text.trim(),
              reason: _reason.text.trim(),
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ReliabilitySummary extends StatelessWidget {
  const _ReliabilitySummary({required this.worker});

  final WorkerProfile worker;

  @override
  Widget build(BuildContext context) {
    final score = worker.reliabilityScore;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reliability', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(score == null ? 'Score unrated' : 'Score ${score.round()}'),
        Text(worker.reliabilityState.label(worker.reliabilitySampleCount)),
        Text(
          '${worker.reliabilityPresentCount} present, '
          '${worker.reliabilityLateCount} late, '
          '${worker.reliabilityAbsentCount} absent',
        ),
        Text(
          '${worker.reliabilityWorkerCancellationCount} worker cancellations, '
          '${worker.reliabilityCompletedEventCount} completed events',
        ),
        Text(
          worker.reliabilityPerformanceAverage == null
              ? '${worker.reliabilityPerformanceEventCount} reviewed events'
              : '${worker.reliabilityPerformanceEventCount} reviewed events, '
                    '${worker.reliabilityPerformanceAverage!.toStringAsFixed(2)} avg',
        ),
        if (worker.reliabilityConfigVersion != null)
          Text('Config v${worker.reliabilityConfigVersion}'),
      ],
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({this.title = 'Reason required'});

  final String title;

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
      title: Text(widget.title),
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

class _CategoryChangeRequest {
  const _CategoryChangeRequest({
    required this.newCategory,
    required this.reason,
  });

  final WorkerCategory newCategory;
  final String reason;
}

class _CategoryChangeDialog extends StatefulWidget {
  const _CategoryChangeDialog({
    required this.currentCategory,
    required this.options,
  });

  final WorkerCategory currentCategory;
  final List<WorkerCategory> options;

  @override
  State<_CategoryChangeDialog> createState() => _CategoryChangeDialogState();
}

class _CategoryChangeDialogState extends State<_CategoryChangeDialog> {
  late WorkerCategory _selectedCategory = widget.options.first;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change category'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Current ${widget.currentCategory.label}'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<WorkerCategory>(
            initialValue: _selectedCategory,
            decoration: const InputDecoration(labelText: 'New category'),
            items: [
              for (final category in widget.options)
                DropdownMenuItem(value: category, child: Text(category.label)),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedCategory = value);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Reason'),
            autofocus: true,
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _CategoryChangeRequest(
              newCategory: _selectedCategory,
              reason: _reason.text.trim(),
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
