import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../events/domain/event_summary.dart';
import '../data/attendance_repository.dart';

final fieldEventsProvider = FutureProvider<List<EventSummary>>(
  (ref) => ref.watch(attendanceRepositoryProvider).loadFieldEvents(),
);

class FieldEventListScreen extends ConsumerWidget {
  const FieldEventListScreen({required this.basePath, super.key});

  final String basePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(fieldEventsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Field events')),
      body: SafeArea(
        child: events.when(
          data: (items) {
            if (items.isEmpty) {
              return const Center(child: Text('No assigned events'));
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
                    '${formatKolkataDateTime12h(event.reportingAt)}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.fact_check),
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
