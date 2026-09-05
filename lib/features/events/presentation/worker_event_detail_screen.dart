import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../booking/domain/booking_application_result.dart';
import '../data/event_repository.dart';
import '../domain/event_summary.dart';
import '../domain/worker_event.dart';
import 'worker_event_list_screen.dart';

final workerEventDetailProvider = FutureProvider.family<WorkerEvent?, String>((
  ref,
  eventId,
) {
  return ref.watch(eventRepositoryProvider).loadWorkerEventDetail(eventId);
});

class WorkerEventDetailScreen extends ConsumerWidget {
  const WorkerEventDetailScreen({required this.eventId, super.key});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(workerEventDetailProvider(eventId));

    return Scaffold(
      appBar: AppBar(title: const Text('Event detail')),
      body: SafeArea(
        child: event.when(
          data: (value) {
            if (value == null) {
              return const Center(child: Text('Event not found'));
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  value.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(value.eventType),
                Text(value.venueName),
                if (value.mapsUrl != null && value.mapsUrl!.trim().isNotEmpty)
                  Text(value.mapsUrl!),
                const SizedBox(height: 12),
                _InfoRow(
                  label: 'Reporting',
                  value: formatKolkataDateTime12h(value.reportingAt),
                ),
                _InfoRow(
                  label: 'Work starts',
                  value: formatKolkataDateTime12h(value.workStartsAt),
                ),
                _InfoRow(
                  label: 'Expected end',
                  value: formatKolkataDateTime12h(value.expectedEndsAt),
                ),
                _InfoRow(
                  label: 'Wage',
                  value:
                      '${value.currencyCode} ${value.dailyWage.toStringAsFixed(0)}',
                ),
                _InfoRow(
                  label: 'Vacancy',
                  value: '${value.vacancyCount}/${value.requiredWorkerCount}',
                ),
                _InfoRow(
                  label: 'Open categories',
                  value: value.openCategories.isEmpty
                      ? 'None'
                      : value.openCategories.join(', '),
                ),
                if (value.ownTierOpensAt case final opensAt?)
                  _InfoRow(
                    label: 'Your tier opens',
                    value: formatKolkataDateTime12h(opensAt),
                  ),
                _InfoRow(label: 'Status', value: value.actionLabel),
                if (value.instructions != null &&
                    value.instructions!.trim().isNotEmpty)
                  _InfoRow(label: 'Instructions', value: value.instructions!),
                if (value.dressCode != null &&
                    value.dressCode!.trim().isNotEmpty)
                  _InfoRow(label: 'Dress code', value: value.dressCode!),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: value.canApply
                      ? () => _apply(context, ref, value.id)
                      : null,
                  icon: const Icon(Icons.send),
                  label: const Text('Apply'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Join Waitlist'),
                ),
              ],
            );
          },
          error: (error, stackTrace) => Center(child: Text(error.toString())),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    String eventId,
  ) async {
    final idempotencyKey =
        'apply-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final result = await ref
        .read(eventRepositoryProvider)
        .applyForEvent(eventId: eventId, idempotencyKey: idempotencyKey);

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(bookingResultMessage(result))));
    ref.invalidate(workerEventDetailProvider(eventId));
    ref.invalidate(workerEventsProvider);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
