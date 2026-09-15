import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:printing/printing.dart';

import '../../../core/widgets/app_feedback.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../events/domain/event_summary.dart';
import '../data/event_report_pdf.dart';
import '../data/report_repository.dart';
import '../domain/event_report.dart';

final eventReportFilterProvider =
    StateProvider.family<EventReportFilter, String>(
      (ref, eventId) => const EventReportFilter(),
    );

final eventReportProvider =
    FutureProvider.family<EventReport, EventReportQuery>((ref, query) {
      return ref
          .watch(reportRepositoryProvider)
          .loadEventReport(
            query.eventId,
            auditActionFilter: query.filter.actionText,
            auditActorRoleFilter: query.filter.actorRole,
            auditLimit: query.filter.limit,
          );
    });

class EventReportFilter {
  const EventReportFilter({this.actionText, this.actorRole, this.limit = 50});
  final String? actionText;
  final String? actorRole;
  final int limit;

  EventReportFilter copyWith({
    String? actionText,
    String? actorRole,
    int? limit,
    bool clearAction = false,
    bool clearActorRole = false,
  }) {
    return EventReportFilter(
      actionText: clearAction ? null : actionText ?? this.actionText,
      actorRole: clearActorRole ? null : actorRole ?? this.actorRole,
      limit: limit ?? this.limit,
    );
  }
}

class EventReportQuery {
  const EventReportQuery({required this.eventId, required this.filter});
  final String eventId;
  final EventReportFilter filter;

  @override
  bool operator ==(Object other) =>
      other is EventReportQuery &&
      other.eventId == eventId &&
      other.filter.actionText == filter.actionText &&
      other.filter.actorRole == filter.actorRole &&
      other.filter.limit == filter.limit;

  @override
  int get hashCode =>
      Object.hash(eventId, filter.actionText, filter.actorRole, filter.limit);
}

class EventReportScreen extends ConsumerWidget {
  const EventReportScreen({required this.eventId, super.key});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(eventReportFilterProvider(eventId));
    final query = EventReportQuery(eventId: eventId, filter: filter);
    final report = ref.watch(eventReportProvider(query));

    return Scaffold(
      appBar: AppBar(title: const Text('Event report')),
      body: SafeArea(
        child: report.when(
          data: (report) => _ReportBody(report: report, eventId: eventId),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppEmptyState(
                    icon: Icons.summarize_outlined,
                    title: 'Could not load report',
                    message: friendlyAuthError(error),
                    action: OutlinedButton.icon(
                      onPressed: () =>
                          ref.invalidate(eventReportProvider(query)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
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

class _ReportBody extends ConsumerWidget {
  const _ReportBody({required this.report, required this.eventId});

  final EventReport report;
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = report.summary;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(summary.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('${summary.eventType} at ${summary.venueName}'),
        Text(formatKolkataDateTime12h(summary.reportingAt)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoChip(
              icon: Icons.groups,
              label:
                  '${summary.confirmedWorkerCount}/${summary.requiredWorkerCount}',
            ),
            _InfoChip(
              icon: Icons.currency_rupee,
              label:
                  '${summary.currencyCode} ${summary.totalWorkerPayDisplay.toStringAsFixed(0)}',
            ),
            _InfoChip(
              icon: Icons.fact_check,
              label:
                  'P ${summary.attendancePresent} L ${summary.attendanceLate} A ${summary.attendanceAbsent}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _copySummary(context, report),
          icon: const Icon(Icons.copy),
          label: const Text('Copy summary'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _exportPdf(context, report),
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Export PDF'),
        ),
        const SizedBox(height: 24),
        _AuditFilters(eventId: eventId),
        const SizedBox(height: 24),
        Text('Staffing', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final row in report.staffing) _StaffingTile(row: row),
        const SizedBox(height: 24),
        Text('History', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final row in report.auditHistory)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: Text(row.action),
            subtitle: Text(
              [
                formatKolkataDateTime12h(row.createdAt),
                row.historySource,
                if (row.actorRole != null) row.actorRole!,
                if (row.reason != null) row.reason!,
              ].join(' • '),
            ),
          ),
        if (report.auditHistory.length >=
            ref.watch(eventReportFilterProvider(eventId)).limit)
          OutlinedButton.icon(
            onPressed: () {
              final current = ref.read(eventReportFilterProvider(eventId));
              ref.read(eventReportFilterProvider(eventId).notifier).state =
                  current.copyWith(limit: current.limit + 50);
            },
            icon: const Icon(Icons.expand_more),
            label: const Text('Load more history'),
          ),
      ],
    );
  }

  Future<void> _copySummary(BuildContext context, EventReport report) async {
    await Clipboard.setData(ClipboardData(text: buildEventReportText(report)));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Summary copied')));
  }

  Future<void> _exportPdf(BuildContext context, EventReport report) async {
    final bytes = await buildEventReportPdf(report);
    await Printing.sharePdf(bytes: bytes, filename: _pdfFileName(report));
  }

  String _pdfFileName(EventReport report) {
    final safeTitle = report.summary.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '${safeTitle.isEmpty ? 'event' : safeTitle}-report.pdf';
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}

class _StaffingTile extends StatelessWidget {
  const _StaffingTile({required this.row});

  final StaffingReportRow row;

  @override
  Widget build(BuildContext context) {
    final workerNumber = row.workerNumber == null
        ? '-'
        : '#${row.workerNumber}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Text(row.categoryAtConfirmation.databaseValue),
      ),
      title: Text('$workerNumber ${row.fullName}'),
      subtitle: Text('${row.phoneE164} • ${row.attendanceStatus.label}'),
      trailing: Text(
        '${row.currencyCode} ${row.totalPayDisplay.toStringAsFixed(0)}',
      ),
    );
  }
}

class _AuditFilters extends ConsumerStatefulWidget {
  const _AuditFilters({required this.eventId});
  final String eventId;
  @override
  ConsumerState<_AuditFilters> createState() => _AuditFiltersState();
}

class _AuditFiltersState extends ConsumerState<_AuditFilters> {
  late final TextEditingController _action;

  @override
  void initState() {
    super.initState();
    _action = TextEditingController(
      text:
          ref.read(eventReportFilterProvider(widget.eventId)).actionText ?? '',
    );
  }

  @override
  void dispose() {
    _action.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(eventReportFilterProvider(widget.eventId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'History filters',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextField(
              controller: _action,
              decoration: const InputDecoration(labelText: 'Action contains'),
              onSubmitted: _applyAction,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All roles'),
                  selected: filter.actorRole == null,
                  onSelected: (_) => _setRole(null),
                ),
                for (final role in [
                  'ADMIN',
                  'SUPER_ADMIN',
                  'CAPTAIN',
                  'SUPERVISOR',
                ])
                  ChoiceChip(
                    label: Text(role),
                    selected: filter.actorRole == role,
                    onSelected: (_) => _setRole(role),
                  ),
                OutlinedButton(
                  onPressed: () => _applyAction(_action.text),
                  child: const Text('Apply'),
                ),
                TextButton(onPressed: _clear, child: const Text('Clear')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _applyAction(String value) {
    final trimmed = value.trim();
    final current = ref.read(eventReportFilterProvider(widget.eventId));
    ref.read(eventReportFilterProvider(widget.eventId).notifier).state = current
        .copyWith(
          actionText: trimmed.isEmpty ? null : trimmed,
          limit: 50,
          clearAction: trimmed.isEmpty,
        );
  }

  void _setRole(String? role) {
    final current = ref.read(eventReportFilterProvider(widget.eventId));
    ref.read(eventReportFilterProvider(widget.eventId).notifier).state = current
        .copyWith(actorRole: role, limit: 50, clearActorRole: role == null);
  }

  void _clear() {
    _action.clear();
    ref.read(eventReportFilterProvider(widget.eventId).notifier).state =
        const EventReportFilter();
  }
}
