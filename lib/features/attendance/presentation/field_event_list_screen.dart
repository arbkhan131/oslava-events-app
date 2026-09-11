import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../events/domain/event_summary.dart';
import '../data/attendance_repository.dart';
import '../domain/attendance_roster.dart';

final fieldEventsProvider = FutureProvider<List<EventSummary>>(
  (ref) => ref.watch(attendanceRepositoryProvider).loadFieldEvents(),
);

final fieldEventDashboardProvider = FutureProvider<FieldEventDashboard>(
  (ref) => ref.watch(attendanceRepositoryProvider).loadFieldDashboard(),
);

class FieldEventListScreen extends ConsumerWidget {
  const FieldEventListScreen({required this.basePath, super.key});

  final String basePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(fieldEventsProvider);
    final dashboard = ref.watch(fieldEventDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Field events'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(fieldEventsProvider);
              ref.invalidate(fieldEventDashboardProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(fieldEventsProvider);
            ref.invalidate(fieldEventDashboardProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              dashboard.when(
                data: (item) => _DashboardCard(dashboard: item),
                error: (error, _) => _InlineError(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(fieldEventDashboardProvider),
                ),
                loading: () => const LinearProgressIndicator(),
              ),
              const SizedBox(height: 12),
              events.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 64),
                      child: Center(child: Text('No assigned events')),
                    );
                  }

                  return Column(
                    children: [
                      for (final event in items)
                        Card(
                          child: ListTile(
                            title: Text(event.title),
                            subtitle: Text(
                              '${event.venueName}\n'
                              '${formatKolkataDateTime12h(event.reportingAt)} · '
                              '${event.eventStatus.databaseValue}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.fact_check),
                            onTap: () =>
                                context.go('$basePath/events/${event.id}'),
                          ),
                        ),
                    ],
                  );
                },
                error: (error, _) => _InlineError(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(fieldEventsProvider),
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.only(top: 64),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.dashboard});
  final FieldEventDashboard dashboard;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today field dashboard',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Events: ${dashboard.assignedTodayCount}')),
              Chip(label: Text('Required: ${dashboard.requiredTodayCount}')),
              Chip(label: Text('Filled: ${dashboard.confirmedTodayCount}')),
              Chip(label: Text('Open marks: ${dashboard.attendanceNotMarked}')),
              Chip(label: Text('Present: ${dashboard.attendancePresent}')),
              Chip(label: Text('Late: ${dashboard.attendanceLate}')),
              Chip(label: Text('Absent: ${dashboard.attendanceAbsent}')),
            ],
          ),
        ],
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.error_outline),
      title: Text(message),
      trailing: OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
    ),
  );
}
