import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_feedback.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../data/worker_repository.dart';
import '../domain/worker_profile.dart';

final ownWorkerProfileProvider = FutureProvider<WorkerProfile>(
  (ref) => ref.watch(workerRepositoryProvider).loadOwnWorkerProfile(),
);

final myErasureRequestsProvider =
    FutureProvider.autoDispose<List<ErasureRequestStatus>>(
      (ref) => ref.watch(workerRepositoryProvider).loadMyErasureRequests(),
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
              _ReliabilitySection(worker: worker),
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
              const SizedBox(height: 16),
              const _PrivacyAndDeletionSection(),
            ],
          ),
          error: (error, stackTrace) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AppEmptyState(
                icon: Icons.person_off_outlined,
                title: 'Could not load profile',
                message: friendlyAuthError(error),
                action: OutlinedButton.icon(
                  onPressed: () => ref.invalidate(ownWorkerProfileProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

class _ReliabilitySection extends StatelessWidget {
  const _ReliabilitySection({required this.worker});

  final WorkerProfile worker;

  @override
  Widget build(BuildContext context) {
    final score = worker.reliabilityScore;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reliability', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Score',
            value: score == null ? 'Unrated' : score.round().toString(),
          ),
          _InfoRow(
            label: 'State',
            value: worker.reliabilityState.label(worker.reliabilitySampleCount),
          ),
          _InfoRow(
            label: 'Attendance',
            value:
                '${worker.reliabilityPresentCount} present, '
                '${worker.reliabilityLateCount} late, '
                '${worker.reliabilityAbsentCount} absent',
          ),
          _InfoRow(
            label: 'Cancellations',
            value: worker.reliabilityWorkerCancellationCount.toString(),
          ),
          _InfoRow(
            label: 'Completed',
            value: worker.reliabilityCompletedEventCount.toString(),
          ),
          _InfoRow(
            label: 'Reviews',
            value: worker.reliabilityPerformanceAverage == null
                ? '${worker.reliabilityPerformanceEventCount} events'
                : '${worker.reliabilityPerformanceEventCount} events, '
                      '${worker.reliabilityPerformanceAverage!.toStringAsFixed(2)} avg',
          ),
        ],
      ),
    );
  }
}

class _WorkerHeader extends StatelessWidget {
  const _WorkerHeader({required this.worker});

  final WorkerProfile worker;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfilePhoto(path: worker.profilePhotoPath),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                worker.fullName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text('Worker ID ${worker.workerNumber ?? '-'}'),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfilePhoto extends ConsumerWidget {
  const _ProfilePhoto({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String?>(
      future: ref.read(workerRepositoryProvider).signedProfilePhotoUrl(path),
      builder: (context, snapshot) {
        final url = snapshot.data;
        return CircleAvatar(
          radius: 36,
          backgroundImage: url == null ? null : NetworkImage(url),
          child: url == null ? const Icon(Icons.person) : null,
        );
      },
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

class _PrivacyAndDeletionSection extends ConsumerStatefulWidget {
  const _PrivacyAndDeletionSection();

  @override
  ConsumerState<_PrivacyAndDeletionSection> createState() =>
      _PrivacyAndDeletionSectionState();
}

class _PrivacyAndDeletionSectionState
    extends ConsumerState<_PrivacyAndDeletionSection> {
  bool submitting = false;

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(myErasureRequestsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Privacy and deletion',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'You can ask Oslava Events to correct your profile data or start account deletion review. Deletion requests are verified first; app access is not disabled by submitting this form.',
            ),
            const SizedBox(height: 12),
            requests.when(
              data: (items) => _ErasureStatusList(items: items),
              error: (error, _) => Text(
                'Could not load request status: ${friendlyAuthError(error)}',
              ),
              loading: () => const LinearProgressIndicator(),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: submitting ? null : _requestDeletion,
              icon: const Icon(Icons.privacy_tip_outlined),
              label: Text(
                submitting ? 'Submitting request…' : 'Request account deletion',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestDeletion() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _DeletionRequestDialog(),
    );
    if (reason == null || reason.trim().isEmpty) return;
    setState(() => submitting = true);
    try {
      await ref.read(workerRepositoryProvider).requestMyAccountErasure(reason);
      ref.invalidate(myErasureRequestsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deletion request submitted for verification.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not submit request: ${friendlyAuthError(error)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }
}

class _ErasureStatusList extends StatelessWidget {
  const _ErasureStatusList({required this.items});

  final List<ErasureRequestStatus> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('No deletion request is currently open.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items.take(3)) ...[
          Text(item.label, style: Theme.of(context).textTheme.labelLarge),
          Text('Due by ${item.dueAt.toLocal().toString().split('.').first}'),
          if (item.completionNotes != null) Text(item.completionNotes!),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _DeletionRequestDialog extends StatefulWidget {
  const _DeletionRequestDialog();

  @override
  State<_DeletionRequestDialog> createState() => _DeletionRequestDialogState();
}

class _DeletionRequestDialogState extends State<_DeletionRequestDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request account deletion'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tell us why you are requesting deletion. An authorized team member must verify the request before account data is fulfilled under the retention policy.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Reason',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
