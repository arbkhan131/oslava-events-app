import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/event_repository.dart';
import '../domain/event_summary.dart';
import 'admin_event_list_screen.dart';

class AdminEventDetailScreen extends ConsumerWidget {
  const AdminEventDetailScreen({required this.eventId, super.key});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(adminEventsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Event detail')),
      body: SafeArea(
        child: events.when(
          data: (items) {
            final event = items.where((item) => item.id == eventId).firstOrNull;
            if (event == null) {
              return const Center(child: Text('Event not found'));
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  event.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(event.eventType),
                Text(event.venueName),
                Text(formatKolkataDateTime12h(event.reportingAt)),
                Text(
                  '${event.currencyCode} ${event.dailyWage.toStringAsFixed(0)}',
                ),
                Text('Workers ${event.requiredWorkerCount}'),
                Text('Lifecycle ${event.eventStatus.databaseValue}'),
                Text('Recruitment ${event.recruitmentStatus.databaseValue}'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: event.eventStatus == EventStatus.draft
                          ? () => _publish(ref, event.id)
                          : null,
                      icon: const Icon(Icons.publish),
                      label: const Text('Publish'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          event.eventStatus == EventStatus.cancelled ||
                              event.eventStatus == EventStatus.closed ||
                              event.eventStatus == EventStatus.completed
                          ? null
                          : () => _cancel(context, ref, event.id),
                      icon: const Icon(Icons.cancel),
                      label: const Text('Cancel'),
                    ),
                    OutlinedButton.icon(
                      onPressed: event.eventStatus == EventStatus.inProgress
                          ? () => _reasonedAction(
                              context,
                              ref,
                              'Complete event',
                              (repository, reason) => repository.completeEvent(
                                eventId: event.id,
                                reason: reason,
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.done_all),
                      label: const Text('Complete'),
                    ),
                    OutlinedButton.icon(
                      onPressed: event.eventStatus == EventStatus.completed
                          ? () => _reasonedAction(
                              context,
                              ref,
                              'Close event',
                              (repository, reason) => repository.closeEvent(
                                eventId: event.id,
                                reason: reason,
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.lock),
                      label: const Text('Close'),
                    ),
                  ],
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

  Future<void> _publish(WidgetRef ref, String id) async {
    await ref.read(eventRepositoryProvider).publishEvent(id);
    ref.invalidate(adminEventsProvider);
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, String id) async {
    await _reasonedAction(
      context,
      ref,
      'Cancel event',
      (repository, reason) =>
          repository.cancelEvent(eventId: id, reason: reason),
    );
  }

  Future<void> _reasonedAction(
    BuildContext context,
    WidgetRef ref,
    String title,
    Future<void> Function(EventRepository repository, String reason) action,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _ReasonDialog(title: title),
    );
    if (reason == null || reason.trim().isEmpty) {
      return;
    }
    await action(ref.read(eventRepositoryProvider), reason);
    ref.invalidate(adminEventsProvider);
  }
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
  Widget build(BuildContext context) {
    return AlertDialog(
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
}
