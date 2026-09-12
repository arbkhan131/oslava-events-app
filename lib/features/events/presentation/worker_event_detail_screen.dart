import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../booking/domain/booking_application_result.dart';
import '../../booking/domain/friend_booking.dart';
import '../../booking/domain/settle_booking.dart';
import '../../booking/domain/waitlist_result.dart';
import '../data/event_repository.dart';
import '../domain/event_summary.dart';
import '../domain/worker_event.dart';
import 'worker_event_list_screen.dart';
import 'worker_my_work_screen.dart';

final workerEventDetailProvider = FutureProvider.family<WorkerEvent?, String>((
  ref,
  eventId,
) {
  return ref.watch(eventRepositoryProvider).loadWorkerEventDetail(eventId);
});

class WorkerEventDetailScreen extends ConsumerStatefulWidget {
  const WorkerEventDetailScreen({required this.eventId, super.key});

  final String eventId;

  @override
  ConsumerState<WorkerEventDetailScreen> createState() =>
      _WorkerEventDetailState();
}

class _WorkerEventDetailState extends ConsumerState<WorkerEventDetailScreen> {
  bool _busy = true;
  bool _lateAcknowledged = false;
  String? _attemptKey;
  BookingApplicationResult? _pending;
  String? _bookingMessage;
  final Set<String> _acknowledgedRequirements = {};
  String get eventId => widget.eventId;

  @override
  void initState() {
    super.initState();
    Future.microtask(_resume);
  }

  Future<void> _resume() async {
    try {
      final pending = await ref
          .read(eventRepositoryProvider)
          .loadPendingBooking(eventId);
      if (!mounted) return;
      if (pending != null) await _settle(pending);
    } catch (_) {
      if (mounted) {
        _bookingMessage =
            'Could not check your application. Retry to check safely.';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _settle(BookingApplicationResult initial) async {
    if (!mounted) return;
    setState(() {
      _pending = initial.isPending ? initial : null;
      _bookingMessage = bookingResultMessage(initial);
    });
    final result = await settleBooking(
      initial,
      fetch: ref.read(eventRepositoryProvider).getBookingResult,
    );
    if (!mounted) return;
    setState(() {
      _pending = result.isPending ? result : null;
      _bookingMessage = bookingResultMessage(result);
      if (!result.isPending) _attemptKey = null;
    });
    _invalidate(eventId);
  }

  @override
  Widget build(BuildContext context) {
    final event = ref.watch(workerEventDetailProvider(eventId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Event detail'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(workerEventDetailProvider(eventId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: event.when(
          data: (value) {
            if (value == null) {
              return const Center(child: Text('Event not found'));
            }
            final missingRequiredAcknowledgement = value.requirements.any(
              (item) =>
                  item.isMandatory &&
                  item.acknowledgementRequired &&
                  !_acknowledgedRequirements.contains(item.id),
            );
            return RefreshIndicator(
              onRefresh: () =>
                  ref.refresh(workerEventDetailProvider(eventId).future),
              child: ListView(
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
                  _InfoCard(
                    title: 'Schedule',
                    rows: [
                      _InfoRowData(
                        'Reporting',
                        formatKolkataDateTime12h(value.reportingAt),
                      ),
                      _InfoRowData(
                        'Work starts',
                        formatKolkataDateTime12h(value.workStartsAt),
                      ),
                      _InfoRowData(
                        'Expected end',
                        formatKolkataDateTime12h(value.expectedEndsAt),
                      ),
                    ],
                  ),
                  _InfoCard(
                    title: 'Pay and staffing',
                    rows: [
                      _InfoRowData(
                        'Wage',
                        '${value.currencyCode} ${value.dailyWage.toStringAsFixed(0)}',
                      ),
                      _InfoRowData(
                        'Vacancy',
                        '${value.vacancyCount}/${value.requiredWorkerCount}',
                      ),
                      _InfoRowData(
                        'Open categories',
                        value.openCategories.isEmpty
                            ? 'None'
                            : value.openCategories.join(', '),
                      ),
                      if (value.ownTierOpensAt case final opensAt?)
                        _InfoRowData(
                          'Your tier opens',
                          formatKolkataDateTime12h(opensAt),
                        ),
                      _InfoRowData('Status', value.actionLabel),
                      if (value.ownWaitlistPosition != null)
                        _InfoRowData(
                          'Waitlist position',
                          '${value.ownWaitlistPosition}',
                        ),
                    ],
                  ),
                  if (value.instructions?.trim().isNotEmpty == true)
                    _TextCard(title: 'Instructions', text: value.instructions!),
                  if (value.dressCode?.trim().isNotEmpty == true)
                    _TextCard(title: 'Dress code', text: value.dressCode!),
                  _RequirementsCard(
                    requirements: value.requirements,
                    acknowledged: _acknowledgedRequirements,
                    onChanged: (id, checked) => setState(() {
                      if (checked) {
                        _acknowledgedRequirements.add(id);
                      } else {
                        _acknowledgedRequirements.remove(id);
                      }
                    }),
                  ),
                  _AllowancesCard(allowances: value.allowances),
                  _LeadersCard(leaders: value.leaders),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _lateAcknowledged,
                    onChanged: _busy
                        ? null
                        : (value) => setState(
                            () => _lateAcknowledged = value ?? false,
                          ),
                    title: const Text(
                      'I understand late booking/cancellation rules',
                    ),
                    subtitle: const Text(
                      'Required if the server says this event is inside a late-booking window.',
                    ),
                  ),
                  if (_bookingMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _bookingMessage!,
                        semanticsLabel: _bookingMessage,
                      ),
                    ),
                  FilledButton.icon(
                    onPressed:
                        !_busy &&
                            !missingRequiredAcknowledgement &&
                            (value.canApply ||
                                _pending != null ||
                                _attemptKey != null)
                        ? () => _apply(value.id)
                        : null,
                    icon: const Icon(Icons.send),
                    label: Text(
                      _busy
                          ? 'Checking application…'
                          : _pending != null || _attemptKey != null
                          ? 'Check application'
                          : missingRequiredAcknowledgement
                          ? 'Acknowledge requirements'
                          : 'Apply',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed:
                        !_busy &&
                            _pending == null &&
                            _attemptKey == null &&
                            value.canApply &&
                            value.vacancyCount >= 2 &&
                            !missingRequiredAcknowledgement
                        ? () => _joinWithFriend(value)
                        : null,
                    icon: const Icon(Icons.group_add),
                    label: Text(
                      missingRequiredAcknowledgement
                          ? 'Acknowledge requirements'
                          : value.vacancyCount < 2
                          ? 'Join with friend needs 2 vacancies'
                          : 'Join with friend',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed:
                        !_busy &&
                            _pending == null &&
                            _attemptKey == null &&
                            value.canJoinWaitlist &&
                            !missingRequiredAcknowledgement
                        ? () => _joinWaitlist(value.id)
                        : null,
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Join Waitlist'),
                  ),
                  const SizedBox(height: 8),
                  if (value.ownWaitlistEntryId != null)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _withdrawWaitlist(value.ownWaitlistEntryId!),
                      icon: const Icon(Icons.playlist_remove),
                      label: const Text('Withdraw waitlist'),
                    ),
                ],
              ),
            );
          },
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
                        ref.invalidate(workerEventDetailProvider(eventId)),
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

  Future<void> _apply(String eventId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repository = ref.read(eventRepositoryProvider);
      final BookingApplicationResult result;
      if (_pending != null) {
        result = await repository.getBookingResult(_pending!.bookingRequestId);
      } else {
        _attemptKey ??=
            'apply-${DateTime.now().toUtc().microsecondsSinceEpoch}';
        result = await repository.applyForEvent(
          eventId: eventId,
          idempotencyKey: _attemptKey!,
          acknowledgedRequirementIds: _acknowledgedRequirements.toList(),
          lateCancellationAcknowledged: _lateAcknowledged,
        );
      }
      await _settle(result);
    } catch (_) {
      if (mounted) {
        setState(() {
          _bookingMessage = 'Could not confirm the result. Check application to retry the same request.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinWaitlist(String eventId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final idempotencyKey =
          'waitlist-${DateTime.now().toUtc().microsecondsSinceEpoch}';
      final result = await ref
          .read(eventRepositoryProvider)
          .joinWaitlist(
            eventId: eventId,
            idempotencyKey: idempotencyKey,
            acknowledgedRequirementIds: _acknowledgedRequirements.toList(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(waitlistResultMessage(result))));
      _invalidate(eventId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinWithFriend(WorkerEvent event) async {
    if (_busy) return;
    final repository = ref.read(eventRepositoryProvider);
    final friend = await showDialog<FriendWorker>(
      context: context,
      builder: (context) => _JoinWithFriendDialog(
        eventId: event.id,
        search: repository.searchBookableFriendWorkers,
      ),
    );
    if (friend == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await repository.applyForEventWithFriend(
        eventId: event.id,
        friendWorkerId: friend.workerId,
        idempotencyKey:
            'friend-${DateTime.now().toUtc().microsecondsSinceEpoch}',
        acknowledgedRequirementIds: _acknowledgedRequirements.toList(),
        lateCancellationAcknowledged: _lateAcknowledged,
      );
      if (!mounted) return;
      final message = friendBookingResultMessage(result);
      setState(() => _bookingMessage = message);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      _invalidate(event.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bookingMessage =
            'Could not complete the friend booking. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdrawWaitlist(String waitlistEntryId) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ReasonDialog(title: 'Withdraw waitlist'),
    );
    if (reason == null || reason.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final status = await ref
          .read(eventRepositoryProvider)
          .withdrawWaitlist(
            waitlistEntryId: waitlistEntryId,
            reason: reason.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Waitlist ${status.name}.')));
      _invalidate(eventId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invalidate(String eventId) {
    ref.invalidate(workerEventDetailProvider(eventId));
    ref.invalidate(workerEventsProvider);
    ref.invalidate(workerAssignmentsProvider);
    ref.invalidate(workerWaitlistProvider);
  }
}

typedef FriendSearch = Future<List<FriendWorker>> Function({
  required String phoneQuery,
  required String eventId,
});

class _JoinWithFriendDialog extends StatefulWidget {
  const _JoinWithFriendDialog({required this.eventId, required this.search});

  final String eventId;
  final FriendSearch search;

  @override
  State<_JoinWithFriendDialog> createState() => _JoinWithFriendDialogState();
}

class _JoinWithFriendDialogState extends State<_JoinWithFriendDialog> {
  final _phone = TextEditingController();
  bool _searching = false;
  String? _error;
  List<FriendWorker> _results = const [];

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _phone.text.trim();
    final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 4) {
      setState(() {
        _error = 'Enter at least 4 phone digits.';
        _results = const [];
      });
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.search(
        phoneQuery: query,
        eventId: widget.eventId,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _error = results.isEmpty ? 'No approved worker found.' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _error = 'Could not search workers. Check the number and try again.';
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Join with friend'),
    content: SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Friend WhatsApp number',
              prefixText: '+91 ',
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: _searching ? null : _search,
                icon: _searching
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
              ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          Flexible(
            child: _results.isEmpty
                ? const Text('Search by phone number, then choose your friend.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final worker = _results[index];
                      return ListTile(
                        enabled: worker.canBookForEvent,
                        title: Text(worker.fullName),
                        subtitle: Text(
                          [
                            worker.phoneE164,
                            'Category ${worker.category}',
                            if (worker.workerNumber != null)
                              'Worker #${worker.workerNumber}',
                            if (!worker.canBookForEvent)
                              'Category not open yet',
                          ].join(' • '),
                        ),
                        trailing: worker.canBookForEvent
                            ? const Icon(Icons.chevron_right)
                            : const Icon(Icons.lock_outline),
                        onTap: worker.canBookForEvent
                            ? () => Navigator.of(context).pop(worker)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
    ],
  );
}

class _InfoRowData {
  const _InfoRowData(this.label, this.value);
  final String label;
  final String value;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.rows});
  final String title;
  final List<_InfoRowData> rows;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      row.label,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  Expanded(child: Text(row.value)),
                ],
              ),
            ),
        ],
      ),
    ),
  );
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

class _RequirementsCard extends StatelessWidget {
  const _RequirementsCard({
    required this.requirements,
    required this.acknowledged,
    required this.onChanged,
  });
  final List<WorkerEventRequirement> requirements;
  final Set<String> acknowledged;
  final void Function(String id, bool checked) onChanged;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Requirements', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (requirements.isEmpty)
            const Text('No special requirements')
          else
            for (final item in requirements)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value:
                    !item.acknowledgementRequired ||
                    acknowledged.contains(item.id),
                onChanged: item.acknowledgementRequired
                    ? (value) => onChanged(item.id, value ?? false)
                    : null,
                title: Text(item.name),
                subtitle: Text(
                  '${item.description ?? ''}${item.extraAllowanceAmount > 0 ? '\nExtra ${item.currencyCode} ${item.extraAllowanceAmount.toStringAsFixed(0)}' : ''}',
                ),
              ),
        ],
      ),
    ),
  );
}

class _AllowancesCard extends StatelessWidget {
  const _AllowancesCard({required this.allowances});
  final List<WorkerEventAllowance> allowances;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Allowances', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (allowances.isEmpty)
            const Text('No extra allowances')
          else
            for (final item in allowances)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.label),
                subtitle: Text(
                  '${item.description ?? ''}\n${item.currencyCode} ${item.amount.toStringAsFixed(0)}',
                ),
              ),
        ],
      ),
    ),
  );
}

class _LeadersCard extends StatelessWidget {
  const _LeadersCard({required this.leaders});
  final List<WorkerEventLeader> leaders;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Event leaders', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (leaders.isEmpty)
            const Text('Leaders will be shared by the organiser')
          else
            for (final leader in leaders)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(leader.fullName),
                subtitle: Text(leader.leaderRole),
              ),
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
