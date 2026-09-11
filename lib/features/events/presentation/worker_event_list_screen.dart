import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/event_repository.dart';
import '../domain/event_summary.dart';
import '../domain/worker_event.dart';

final workerEventsProvider = FutureProvider<List<WorkerEvent>>(
  (ref) => ref.watch(eventRepositoryProvider).loadWorkerEvents(),
);

class WorkerEventListScreen extends ConsumerWidget {
  const WorkerEventListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(workerEventsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      body: SafeArea(
        child: events.when(
          data: (items) {
            if (items.isEmpty) {
              return const Center(child: Text('No visible events'));
            }
            return RefreshIndicator(
              onRefresh: () => ref.refresh(workerEventsProvider.future),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final event = items[index];
                  return Card(
                    child: ListTile(
                      title: Text(event.title),
                      subtitle: Text(
                        '${event.venueName}\n'
                        'Report ${formatKolkataDateTime12h(event.reportingAt)} · '
                        '${event.currencyCode} ${event.dailyWage.toStringAsFixed(0)}\n'
                        '${event.vacancyCount} vacant · '
                        '${event.openCategories.isEmpty ? 'No categories open' : 'Open: ${event.openCategories.join(', ')}'}'
                        '${_tierText(event)}',
                      ),
                      isThreeLine: true,
                      trailing: _ActionChip(event: event),
                      onTap: () => context.go('/worker/events/${event.id}'),
                    ),
                  );
                },
              ),
            );
          },
          error: (error, stackTrace) => Center(child: Text(error.toString())),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.event});

  final WorkerEvent event;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (event.actionState) {
      WorkerEventActionState.available => colors.primary,
      WorkerEventActionState.full => colors.tertiary,
      WorkerEventActionState.locked => colors.outline,
      WorkerEventActionState.confirmed => colors.secondary,
      WorkerEventActionState.waitlisted => colors.tertiary,
      WorkerEventActionState.completed => colors.outline,
      WorkerEventActionState.cancelled => colors.error,
      WorkerEventActionState.closed => colors.outline,
    };

    return Chip(
      side: BorderSide(color: color),
      label: Text(event.actionLabel),
      labelStyle: TextStyle(color: color),
    );
  }
}

String _tierText(WorkerEvent event) {
  if (event.actionState != WorkerEventActionState.locked ||
      event.ownTierOpensAt == null) {
    return '';
  }
  final remaining = timeUntilTierOpens(
    opensAt: event.ownTierOpensAt!,
    now: DateTime.now().toUtc(),
  );
  if (remaining == Duration.zero) return ' · refresh to apply';
  final hours = remaining.inHours;
  final minutes = remaining.inMinutes.remainder(60);
  return ' · your tier opens in ${hours}h ${minutes}m';
}
