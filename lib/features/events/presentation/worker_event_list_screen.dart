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
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Events')),
    body: SafeArea(
      child: ref
          .watch(workerEventsProvider)
          .when(
            data: (items) => RefreshIndicator(
              onRefresh: () => ref.refresh(workerEventsProvider.future),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                itemCount: items.isEmpty ? 1 : items.length,
                itemBuilder: (context, index) {
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 64),
                      child: Column(
                        children: [
                          Icon(
                            Icons.event_available_outlined,
                            size: 56,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'No visible events',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Check back for upcoming work. Pull down to refresh.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }
                  final event = items[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.go('/worker/events/${event.id}'),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ActionChip(event: event),
                            const SizedBox(height: 12),
                            Text(
                              event.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            _EventInfo(
                              icon: Icons.location_on_outlined,
                              text: event.venueName,
                            ),
                            const SizedBox(height: 8),
                            _EventInfo(
                              icon: Icons.schedule_outlined,
                              text:
                                  'Report ${formatKolkataDateTime12h(event.reportingAt)}',
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Divider(height: 1),
                            ),
                            Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                Text(
                                  '${event.currencyCode} ${event.dailyWage.toStringAsFixed(0)} / day',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text('${event.vacancyCount} vacant'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${event.openCategories.isEmpty ? 'No categories open' : 'Open: ${event.openCategories.join(', ')}'}${_tierText(event)}',
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'View event →',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            error: (_, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 40),
                    const SizedBox(height: 16),
                    const Text(
                      'Could not load events. Check your connection and try again.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(workerEventsProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
    ),
  );
}

class _EventInfo extends StatelessWidget {
  const _EventInfo({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        icon,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(text)),
    ],
  );
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.event});
  final WorkerEvent event;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (event.actionState) {
      WorkerEventActionState.available => colors.primary,
      WorkerEventActionState.confirmed => colors.secondary,
      WorkerEventActionState.full ||
      WorkerEventActionState.waitlisted => colors.tertiary,
      WorkerEventActionState.cancelled => colors.error,
      _ => colors.onSurfaceVariant,
    };
    return Chip(
      backgroundColor: color.withValues(alpha: 0.08),
      label: Text(event.actionLabel),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
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
  return ' · your tier opens in ${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m';
}
