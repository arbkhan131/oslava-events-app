import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/event_repository.dart';
import '../domain/event_summary.dart';

final adminEventsProvider = FutureProvider<List<EventSummary>>(
  (ref) => ref.watch(eventRepositoryProvider).loadAdminEvents(),
);

class AdminEventListScreen extends ConsumerWidget {
  const AdminEventListScreen({required this.basePath, super.key});

  final String basePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(adminEventsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Events'),
        actions: [
          IconButton(
            tooltip: 'Create event',
            onPressed: () => context.go('$basePath/events/new'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: SafeArea(
        child: events.when(
          data: (items) {
            if (items.isEmpty) {
              return const Center(child: Text('No events yet'));
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final event = items[index];
                return ListTile(
                  title: Text(event.title),
                  subtitle: Text(
                    '${event.venueName}\n'
                    '${formatKolkataDateTime12h(event.reportingAt)}  '
                    '${event.currencyCode} ${event.dailyWage.toStringAsFixed(0)}',
                  ),
                  isThreeLine: true,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(event.eventStatus.databaseValue),
                      Text(event.recruitmentStatus.databaseValue),
                    ],
                  ),
                  onTap: () => context.go('$basePath/events/${event.id}'),
                );
              },
            );
          },
          error: (error, stackTrace) => Center(child: Text(error.toString())),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}
