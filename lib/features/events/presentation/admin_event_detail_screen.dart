import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/event_repository.dart';
import '../domain/event_summary.dart';
import 'admin_event_form_screen.dart';
import 'admin_event_list_screen.dart';

class AdminEventDetailScreen extends ConsumerWidget {
  const AdminEventDetailScreen({
    required this.eventId,
    required this.basePath,
    super.key,
  });

  final String eventId;
  final String basePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(adminEventDetailProvider(eventId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event detail'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(adminEventDetailProvider(eventId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: detail.when(
          data: (event) => _DetailBody(event: event, basePath: basePath),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () =>
                        ref.invalidate(adminEventDetailProvider(eventId)),
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
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.event, required this.basePath});

  final AdminEventDetail event;
  final String basePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = event.summary;
    final terminal =
        summary.eventStatus == EventStatus.cancelled ||
        summary.eventStatus == EventStatus.closed ||
        summary.eventStatus == EventStatus.completed;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(summary.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(summary.eventType),
        Text(summary.venueName),
        if (event.mapsUrl?.isNotEmpty == true) Text(event.mapsUrl!),
        const SizedBox(height: 12),
        _InfoCard(
          title: 'Schedule',
          rows: [
            _InfoRow(
              'Reporting',
              formatKolkataDateTime12h(summary.reportingAt),
            ),
            _InfoRow('Starts', formatKolkataDateTime12h(event.workStartsAt)),
            _InfoRow(
              'Expected end',
              formatKolkataDateTime12h(event.expectedEndsAt),
            ),
          ],
        ),
        _InfoCard(
          title: 'Staffing',
          rows: [
            _InfoRow('Required', '${summary.requiredWorkerCount}'),
            _InfoRow('Confirmed', '${event.confirmedCount}'),
            _InfoRow('Waitlist', '${event.waitlistCount}'),
            _InfoRow(
              'Vacant',
              '${(summary.requiredWorkerCount - event.confirmedCount).clamp(0, summary.requiredWorkerCount)}',
            ),
            _InfoRow('Open review flags', '${event.openReviewFlags}'),
          ],
        ),
        _InfoCard(
          title: 'Pay and status',
          rows: [
            _InfoRow(
              'Wage',
              '${summary.currencyCode} ${summary.dailyWage.toStringAsFixed(0)}',
            ),
            _InfoRow('Lifecycle', summary.eventStatus.databaseValue),
            _InfoRow('Recruitment', summary.recruitmentStatus.databaseValue),
            _InfoRow('Tier release', summary.tierStrategy.databaseValue),
            _InfoRow('Version', '${summary.version}'),
          ],
        ),
        if (event.instructions?.isNotEmpty == true)
          _TextCard(title: 'Instructions', text: event.instructions!),
        if (event.dressCode?.isNotEmpty == true)
          _TextCard(title: 'Dress code', text: event.dressCode!),
        _ListCard(
          title: 'Leaders',
          emptyText: 'No leaders assigned',
          children: [
            for (final leader in event.leaders)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(leader.fullName),
                subtitle: Text(leader.leaderRole),
              ),
          ],
        ),
        _ListCard(
          title: 'Requirements',
          emptyText: 'No requirements',
          children: [
            for (final item in event.requirements)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.name),
                subtitle: Text(
                  '${item.description ?? ''}\n'
                  '${item.isMandatory ? 'Mandatory' : 'Optional'} · '
                  '${item.acknowledgementRequired ? 'Acknowledgement required' : 'No acknowledgement'} · '
                  'Extra INR ${item.extraAllowanceAmount.toStringAsFixed(0)}',
                ),
              ),
          ],
        ),
        _ListCard(
          title: 'Allowances',
          emptyText: 'No allowances',
          children: [
            for (final item in event.allowances)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.label),
                subtitle: Text(
                  '${item.description ?? ''}\nINR ${item.amount.toStringAsFixed(0)}',
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: terminal
                  ? null
                  : () => context.go('$basePath/events/${summary.id}/edit'),
              icon: const Icon(Icons.edit),
              label: const Text('Edit'),
            ),
            FilledButton.icon(
              onPressed: summary.eventStatus == EventStatus.draft
                  ? () => _publish(context, ref, summary.id)
                  : null,
              icon: const Icon(Icons.publish),
              label: const Text('Publish'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  context.go('$basePath/events/${summary.id}/attendance'),
              icon: const Icon(Icons.fact_check),
              label: const Text('Attendance'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  context.go('$basePath/events/${summary.id}/report'),
              icon: const Icon(Icons.summarize),
              label: const Text('Report'),
            ),
            OutlinedButton.icon(
              onPressed: terminal
                  ? null
                  : () => _cancel(context, ref, summary.id),
              icon: const Icon(Icons.cancel),
              label: const Text('Cancel'),
            ),
            OutlinedButton.icon(
              onPressed: summary.eventStatus == EventStatus.inProgress
                  ? () => _reasonedAction(
                      context,
                      ref,
                      'Complete event',
                      (repository, reason) => repository.completeEvent(
                        eventId: summary.id,
                        reason: reason,
                      ),
                    )
                  : null,
              icon: const Icon(Icons.done_all),
              label: const Text('Complete'),
            ),
            OutlinedButton.icon(
              onPressed: summary.eventStatus == EventStatus.completed
                  ? () => _reasonedAction(
                      context,
                      ref,
                      'Close event',
                      (repository, reason) => repository.closeEvent(
                        eventId: summary.id,
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
  }

  Future<void> _publish(BuildContext context, WidgetRef ref, String id) async {
    try {
      await ref.read(eventRepositoryProvider).publishEvent(id);
      _invalidate(ref, id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, String id) {
    return _reasonedAction(
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
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await action(ref.read(eventRepositoryProvider), reason.trim());
      _invalidate(ref, event.summary.id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  void _invalidate(WidgetRef ref, String id) {
    ref.invalidate(adminEventsProvider);
    ref.invalidate(adminEventDashboardProvider);
    ref.invalidate(adminEventDetailProvider(id));
  }
}

class _InfoRow {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.rows});
  final String title;
  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(row.label)),
                    Text(row.value),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TextCard extends StatelessWidget {
  const _TextCard({required this.title, required this.text});
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(title: Text(title), subtitle: Text(text)),
  );
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.title,
    required this.emptyText,
    required this.children,
  });
  final String title;
  final String emptyText;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (children.isEmpty) Text(emptyText) else ...children,
        ],
      ),
    ),
  );
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
  Widget build(BuildContext context) => AlertDialog(
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
