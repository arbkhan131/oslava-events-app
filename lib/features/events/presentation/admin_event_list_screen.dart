import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_widgets.dart';
import '../data/event_repository.dart';
import '../domain/event_summary.dart';

final adminEventsProvider = FutureProvider<List<EventSummary>>(
  (ref) => ref.watch(eventRepositoryProvider).loadAdminEvents(),
);

final adminEventDashboardProvider = FutureProvider<AdminEventDashboard>(
  (ref) => ref.watch(eventRepositoryProvider).loadAdminDashboard(),
);

final adminEventStatusFilterProvider = StateProvider<EventStatus?>(
  (ref) => null,
);

class AdminEventListScreen extends ConsumerWidget {
  const AdminEventListScreen({required this.basePath, super.key});

  final String basePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(adminEventsProvider);
    final dashboard = ref.watch(adminEventDashboardProvider);
    final filter = ref.watch(adminEventStatusFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Events'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(adminEventsProvider);
              ref.invalidate(adminEventDashboardProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Create event',
            onPressed: () => context.go('$basePath/events/new'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(adminEventsProvider);
            ref.invalidate(adminEventDashboardProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              dashboard.when(
                data: (item) => _DashboardCard(dashboard: item),
                error: (error, _) => _InlineError(
                  message: friendlyAuthError(error),
                  onRetry: () => ref.invalidate(adminEventDashboardProvider),
                ),
                loading: () => const LinearProgressIndicator(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: filter == null,
                    onSelected: (_) =>
                        ref
                                .read(adminEventStatusFilterProvider.notifier)
                                .state =
                            null,
                  ),
                  for (final status in EventStatus.values)
                    ChoiceChip(
                      label: Text(status.databaseValue),
                      selected: filter == status,
                      onSelected: (_) =>
                          ref
                                  .read(adminEventStatusFilterProvider.notifier)
                                  .state =
                              status,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              events.when(
                data: (items) {
                  final filtered = filter == null
                      ? items
                      : items
                            .where((item) => item.eventStatus == filter)
                            .toList(growable: false);
                  if (filtered.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: Text('No matching events yet')),
                    );
                  }
                  return Column(
                    children: [
                      for (final event in filtered)
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () =>
                                context.go('$basePath/events/${event.id}'),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      Chip(
                                        label: Text(
                                          event.eventStatus.databaseValue,
                                        ),
                                      ),
                                      Chip(
                                        label: Text(
                                          event.recruitmentStatus.databaseValue,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    event.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(event.venueName),
                                  const SizedBox(height: 8),
                                  Text(
                                    formatKolkataDateTime12h(event.reportingAt),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '${event.currencyCode} ${event.dailyWage.toStringAsFixed(0)} / day',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      Chip(
                                        avatar: const Icon(
                                          Icons.groups_outlined,
                                          size: 18,
                                        ),
                                        label: Text(
                                          '${event.confirmedCount}/${event.requiredWorkerCount} filled',
                                        ),
                                      ),
                                      Chip(
                                        avatar: const Icon(
                                          Icons.event_seat_outlined,
                                          size: 18,
                                        ),
                                        label: Text(
                                          '${event.vacantCount ?? (event.requiredWorkerCount - event.confirmedCount).clamp(0, event.requiredWorkerCount)} vacant',
                                        ),
                                      ),
                                      if (event.waitlistCount > 0)
                                        Chip(
                                          avatar: const Icon(
                                            Icons.hourglass_empty,
                                            size: 18,
                                          ),
                                          label: Text(
                                            '${event.waitlistCount} waiting',
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
                error: (error, _) => _InlineError(
                  message: friendlyAuthError(error),
                  onRetry: () => ref.invalidate(adminEventsProvider),
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
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
  final AdminEventDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today staffing dashboard',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Counts below are only for events dated today.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Metric(label: 'Today', value: dashboard.todayEventCount),
                _Metric(label: 'Required', value: dashboard.requiredTodayCount),
                _Metric(label: 'Filled', value: dashboard.confirmedTodayCount),
                _Metric(label: 'Vacant', value: dashboard.vacantTodayCount),
                _Metric(
                  label: 'Open flags',
                  value: dashboard.openReviewFlagCount,
                ),
                _Metric(label: 'Drafts', value: dashboard.draftCount),
                _Metric(label: 'Published', value: dashboard.publishedCount),
                _Metric(label: 'Upcoming', value: dashboard.upcomingCount),
                _Metric(label: 'In progress', value: dashboard.inProgressCount),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) => Chip(label: Text('$label: $value'));
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
