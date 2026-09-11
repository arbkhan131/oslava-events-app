import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_session.dart';
import '../../workers/data/worker_repository.dart';
import '../../workers/domain/worker_profile.dart';
import '../data/event_repository.dart';
import '../domain/event_summary.dart';
import 'admin_event_list_screen.dart';

final adminEventDetailProvider =
    FutureProvider.family<AdminEventDetail, String>(
      (ref, eventId) =>
          ref.watch(eventRepositoryProvider).loadAdminEventDetail(eventId),
    );

final fieldLeaderOptionsProvider = FutureProvider<List<StaffProfile>>((
  ref,
) async {
  final repository = ref.watch(workerRepositoryProvider);
  final staff = await repository.searchStaff(
    accountStatus: AccountStatus.active,
    limit: 100,
  );
  return staff
      .where(
        (member) =>
            member.role == AppRole.captain || member.role == AppRole.supervisor,
      )
      .toList(growable: false);
});

class AdminEventFormScreen extends ConsumerStatefulWidget {
  const AdminEventFormScreen({required this.basePath, this.eventId, super.key});

  final String basePath;
  final String? eventId;

  @override
  ConsumerState<AdminEventFormScreen> createState() =>
      _AdminEventFormScreenState();
}

class _AdminEventFormScreenState extends ConsumerState<AdminEventFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _eventType = TextEditingController();
  final _venue = TextEditingController();
  final _mapsUrl = TextEditingController();
  final _eventDate = TextEditingController();
  final _reportingTime = TextEditingController();
  final _startTime = TextEditingController();
  final _endTime = TextEditingController();
  final _workers = TextEditingController(text: '10');
  final _wage = TextEditingController(text: '1200');
  final _tierA = TextEditingController(text: '0');
  final _tierB = TextEditingController(text: '30');
  final _tierC = TextEditingController(text: '60');
  final _tierF = TextEditingController(text: '180');
  final _instructions = TextEditingController();
  final _dressCode = TextEditingController();
  final List<_LeaderRow> _leaders = [];
  final List<_RequirementRow> _requirements = [];
  final List<_AllowanceRow> _allowances = [];
  TierStrategy _tierStrategy = TierStrategy.standard;
  bool _saving = false;
  String? _loadedEventId;

  @override
  void initState() {
    super.initState();
    final kolkata = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30, days: 7),
    );
    _eventDate.text = _formatDate(kolkata);
    _reportingTime.text = '9:00 AM';
    _startTime.text = '10:00 AM';
    _endTime.text = '6:00 PM';
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _eventType,
      _venue,
      _mapsUrl,
      _eventDate,
      _reportingTime,
      _startTime,
      _endTime,
      _workers,
      _wage,
      _tierA,
      _tierB,
      _tierC,
      _tierF,
      _instructions,
      _dressCode,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editingId = widget.eventId;
    final detail = editingId == null
        ? null
        : ref.watch(adminEventDetailProvider(editingId));
    return Scaffold(
      appBar: AppBar(
        title: Text(editingId == null ? 'New event' : 'Edit event'),
      ),
      body: SafeArea(
        child: detail == null
            ? _form(null)
            : detail.when(
                data: (event) {
                  _loadOnce(event);
                  return _form(event);
                },
                error: (error, _) => _ErrorState(
                  message: error.toString(),
                  onRetry: () =>
                      ref.invalidate(adminEventDetailProvider(editingId!)),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
              ),
      ),
    );
  }

  Widget _form(AdminEventDetail? existing) {
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (existing != null && existing.confirmedCount > 0)
            Card(
              child: ListTile(
                leading: const Icon(Icons.groups),
                title: Text(
                  '${existing.confirmedCount} confirmed, ${existing.waitlistCount} waiting',
                ),
                subtitle: const Text(
                  'Capacity or time edits are checked by the backend. If a change affects assignments, it must go through review instead of silently dropping workers.',
                ),
              ),
            ),
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            validator: _required,
          ),
          TextFormField(
            controller: _eventType,
            decoration: const InputDecoration(labelText: 'Event type'),
            validator: _required,
          ),
          TextFormField(
            controller: _venue,
            decoration: const InputDecoration(labelText: 'Venue'),
            validator: _required,
          ),
          TextFormField(
            controller: _mapsUrl,
            decoration: const InputDecoration(labelText: 'Google Maps URL'),
          ),
          const SizedBox(height: 12),
          Text('Schedule — Asia/Kolkata', style: theme.textTheme.titleMedium),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _eventDate,
                  decoration: const InputDecoration(
                    labelText: 'Event date YYYY-MM-DD',
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                  ],
                  validator: _validDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _reportingTime,
                  decoration: const InputDecoration(
                    labelText: 'Reporting time',
                  ),
                  validator: _validClock,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _startTime,
                  decoration: const InputDecoration(labelText: 'Work starts'),
                  validator: _validClock,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _endTime,
                  decoration: const InputDecoration(labelText: 'Expected ends'),
                  validator: _validClock,
                ),
              ),
            ],
          ),
          Text(
            'Overnight work is allowed: if end time is earlier than start time, it is saved on the next day.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _workers,
                  decoration: const InputDecoration(
                    labelText: 'Workers needed',
                  ),
                  keyboardType: TextInputType.number,
                  validator: _positiveInt,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _wage,
                  decoration: const InputDecoration(
                    labelText: 'Daily wage INR',
                  ),
                  keyboardType: TextInputType.number,
                  validator: _nonNegativeMoney,
                ),
              ),
            ],
          ),
          DropdownButtonFormField<TierStrategy>(
            initialValue: _tierStrategy,
            decoration: const InputDecoration(labelText: 'Tier strategy'),
            items: [
              for (final strategy in TierStrategy.values)
                DropdownMenuItem(
                  value: strategy,
                  child: Text(strategy.databaseValue),
                ),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() {
                    _tierStrategy = value ?? TierStrategy.standard;
                    if (_tierStrategy != TierStrategy.custom) {
                      _applyPresetOffsets(_tierStrategy);
                    }
                  }),
          ),
          if (_tierStrategy == TierStrategy.custom)
            _tierOffsetFields()
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                describeTierReleaseOffsets(
                  TierReleaseOffsets.presetFor(_tierStrategy),
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
          TextFormField(
            controller: _instructions,
            decoration: const InputDecoration(labelText: 'Instructions'),
            maxLines: 3,
          ),
          TextFormField(
            controller: _dressCode,
            decoration: const InputDecoration(labelText: 'Dress code'),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          _leadersSection(),
          const SizedBox(height: 16),
          _requirementsSection(),
          const SizedBox(height: 16),
          _allowancesSection(),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : () => _save(existing),
            icon: const Icon(Icons.save),
            label: Text(
              _saving
                  ? 'Saving...'
                  : existing == null
                  ? 'Save draft'
                  : 'Save changes',
            ),
          ),
        ],
      ),
    );
  }

  Widget _tierOffsetFields() => Column(
    children: [
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _tierA,
              decoration: const InputDecoration(
                labelText: 'A opens after minutes',
              ),
              keyboardType: TextInputType.number,
              validator: _nonNegativeInt,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: _tierB,
              decoration: const InputDecoration(
                labelText: 'B opens after minutes',
              ),
              keyboardType: TextInputType.number,
              validator: _nonNegativeInt,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _tierC,
              decoration: const InputDecoration(
                labelText: 'C opens after minutes',
              ),
              keyboardType: TextInputType.number,
              validator: _nonNegativeInt,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: _tierF,
              decoration: const InputDecoration(
                labelText: 'F opens after minutes',
              ),
              keyboardType: TextInputType.number,
              validator: _nonNegativeInt,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _leadersSection() {
    final staff = ref.watch(fieldLeaderOptionsProvider);
    return _SectionCard(
      title: 'Leaders',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          staff.when(
            data: (items) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final member in items.where(
                  (item) =>
                      !_leaders.any((leader) => leader.userId == item.userId),
                ))
                  ActionChip(
                    label: Text('${member.fullName} · ${member.role.label}'),
                    onPressed: () => setState(
                      () => _leaders.add(
                        _LeaderRow(
                          userId: member.userId,
                          leaderRole: member.role.databaseValue,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            error: (error, _) => Text('Leader picker unavailable: $error'),
            loading: () => const LinearProgressIndicator(),
          ),
          for (var i = 0; i < _leaders.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_leaders[i].userId),
              subtitle: Text(_leaders[i].leaderRole),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => setState(() => _leaders.removeAt(i)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _requirementsSection() => _SectionCard(
    title: 'Requirements and acknowledgement',
    child: Column(
      children: [
        for (var i = 0; i < _requirements.length; i++)
          _RequirementEditor(
            row: _requirements[i],
            onRemove: () => setState(() => _requirements.removeAt(i)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add requirement'),
            onPressed: () =>
                setState(() => _requirements.add(_RequirementRow())),
          ),
        ),
      ],
    ),
  );

  Widget _allowancesSection() => _SectionCard(
    title: 'Allowances',
    child: Column(
      children: [
        for (var i = 0; i < _allowances.length; i++)
          _AllowanceEditor(
            row: _allowances[i],
            onRemove: () => setState(() => _allowances.removeAt(i)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add allowance'),
            onPressed: () => setState(() => _allowances.add(_AllowanceRow())),
          ),
        ),
      ],
    ),
  );

  void _loadOnce(AdminEventDetail event) {
    if (_loadedEventId == event.summary.id) return;
    _loadedEventId = event.summary.id;
    final input = event.toDraftInput();
    _title.text = input.title;
    _eventType.text = input.eventType;
    _venue.text = input.venueName;
    _mapsUrl.text = input.mapsUrl ?? '';
    _eventDate.text = _formatDate(
      input.reportingAt.toUtc().add(const Duration(hours: 5, minutes: 30)),
    );
    _reportingTime.text = _formatTime(input.reportingAt);
    _startTime.text = _formatTime(input.workStartsAt);
    _endTime.text = _formatTime(input.expectedEndsAt);
    _workers.text = input.requiredWorkerCount.toString();
    _wage.text = input.dailyWage.toStringAsFixed(
      input.dailyWage.truncateToDouble() == input.dailyWage ? 0 : 2,
    );
    _tierStrategy = input.tierStrategy;
    _instructions.text = input.instructions ?? '';
    _dressCode.text = input.dressCode ?? '';
    _leaders
      ..clear()
      ..addAll(
        input.leaders.map(
          (leader) =>
              _LeaderRow(userId: leader.userId, leaderRole: leader.leaderRole),
        ),
      );
    _requirements
      ..clear()
      ..addAll(input.requirements.map(_RequirementRow.fromInput));
    _allowances
      ..clear()
      ..addAll(input.allowances.map(_AllowanceRow.fromInput));
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required.' : null;
  String? _positiveInt(String? value) =>
      (int.tryParse(value ?? '') ?? 0) <= 0 ? 'Enter a positive number.' : null;
  String? _nonNegativeMoney(String? value) {
    final parsed = double.tryParse(value ?? '');
    return parsed == null || parsed < 0 ? 'Enter zero or more.' : null;
  }

  String? _nonNegativeInt(String? value) {
    final parsed = int.tryParse(value ?? '');
    return parsed == null || parsed < 0 ? 'Enter zero or more.' : null;
  }

  String? _validDate(String? value) =>
      _parseDate(value ?? '') == null ? 'Use YYYY-MM-DD.' : null;
  String? _validClock(String? value) =>
      _parseClock(value ?? '') == null ? 'Use 9:30 AM or 21:30.' : null;

  void _applyPresetOffsets(TierStrategy strategy) {
    final offsets = TierReleaseOffsets.presetFor(strategy);
    _tierA.text = '${offsets.aMinutes}';
    _tierB.text = '${offsets.bMinutes}';
    _tierC.text = '${offsets.cMinutes}';
    _tierF.text = '${offsets.fMinutes}';
  }

  TierReleaseOffsets _customOffsetsFromForm() => TierReleaseOffsets(
    aMinutes: int.parse(_tierA.text),
    bMinutes: int.parse(_tierB.text),
    cMinutes: int.parse(_tierC.text),
    fMinutes: int.parse(_tierF.text),
  );

  EventDraftInput? _inputFromForm() {
    final date = _parseDate(_eventDate.text);
    final reporting = _parseClock(_reportingTime.text);
    final start = _parseClock(_startTime.text);
    final end = _parseClock(_endTime.text);
    if (date == null || reporting == null || start == null || end == null) {
      return null;
    }
    final reportingAt = _combineKolkata(date, reporting);
    var workStartsAt = _combineKolkata(date, start);
    if (!workStartsAt.isAfter(reportingAt)) {
      workStartsAt = workStartsAt.add(const Duration(days: 1));
    }
    var expectedEndsAt = _combineKolkata(date, end);
    while (!expectedEndsAt.isAfter(workStartsAt)) {
      expectedEndsAt = expectedEndsAt.add(const Duration(days: 1));
    }
    final customOffsets = _tierStrategy == TierStrategy.custom
        ? _customOffsetsFromForm()
        : null;
    return EventDraftInput(
      title: _title.text.trim(),
      eventType: _eventType.text.trim(),
      venueName: _venue.text.trim(),
      mapsUrl: _emptyToNull(_mapsUrl.text),
      reportingAt: reportingAt,
      workStartsAt: workStartsAt,
      expectedEndsAt: expectedEndsAt,
      requiredWorkerCount: int.parse(_workers.text),
      dailyWage: double.parse(_wage.text),
      tierStrategy: _tierStrategy,
      customTierOffsets: customOffsets,
      instructions: _emptyToNull(_instructions.text),
      dressCode: _emptyToNull(_dressCode.text),
      leaders: _leaders
          .map(
            (row) => EventLeaderInput(
              userId: row.userId,
              leaderRole: row.leaderRole,
            ),
          )
          .toList(),
      requirements: _requirements
          .where((row) => row.name.text.trim().isNotEmpty)
          .map((row) => row.toInput())
          .toList(),
      allowances: _allowances
          .where((row) => row.label.text.trim().isNotEmpty)
          .map((row) => row.toInput())
          .toList(),
    );
  }

  Future<void> _save(AdminEventDetail? existing) async {
    if (!_formKey.currentState!.validate()) return;
    final input = _inputFromForm();
    if (input == null) return;
    if (input.customTierOffsets case final offsets? when !offsets.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tier release offsets must expand in A, B, C, F order.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final repository = ref.read(eventRepositoryProvider);
      if (existing == null) {
        await repository.createDraft(input);
      } else {
        await repository.updateEvent(
          eventId: existing.summary.id,
          expectedVersion: existing.summary.version,
          input: input,
          reason: 'Updated from admin event form',
          confirmConflicts: true,
        );
        ref.invalidate(adminEventDetailProvider(existing.summary.id));
      }
      ref.invalidate(adminEventsProvider);
      ref.invalidate(adminEventDashboardProvider);
      if (mounted) {
        context.go('${widget.basePath}/events');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class _LeaderRow {
  _LeaderRow({required this.userId, required this.leaderRole});
  final String userId;
  final String leaderRole;
}

class _RequirementRow {
  _RequirementRow({
    String? name,
    String? description,
    this.isMandatory = true,
    this.acknowledgementRequired = false,
    double extraAllowanceAmount = 0,
  }) : name = TextEditingController(text: name ?? ''),
       description = TextEditingController(text: description ?? ''),
       extraAllowance = TextEditingController(
         text: extraAllowanceAmount == 0 ? '' : extraAllowanceAmount.toString(),
       );
  factory _RequirementRow.fromInput(EventRequirementInput input) =>
      _RequirementRow(
        name: input.name,
        description: input.description,
        isMandatory: input.isMandatory,
        acknowledgementRequired: input.acknowledgementRequired,
        extraAllowanceAmount: input.extraAllowanceAmount,
      );
  final TextEditingController name;
  final TextEditingController description;
  final TextEditingController extraAllowance;
  bool isMandatory;
  bool acknowledgementRequired;
  EventRequirementInput toInput() => EventRequirementInput(
    name: name.text.trim(),
    description: _emptyToNull(description.text),
    isMandatory: isMandatory,
    acknowledgementRequired: acknowledgementRequired,
    extraAllowanceAmount: double.tryParse(extraAllowance.text) ?? 0,
  );
}

class _AllowanceRow {
  _AllowanceRow({String? label, String? description, double amount = 0})
    : label = TextEditingController(text: label ?? ''),
      description = TextEditingController(text: description ?? ''),
      amount = TextEditingController(
        text: amount == 0 ? '' : amount.toString(),
      );
  factory _AllowanceRow.fromInput(EventAllowanceInput input) => _AllowanceRow(
    label: input.label,
    description: input.description,
    amount: input.amount,
  );
  final TextEditingController label;
  final TextEditingController description;
  final TextEditingController amount;
  EventAllowanceInput toInput() => EventAllowanceInput(
    label: label.text.trim(),
    description: _emptyToNull(description.text),
    amount: double.tryParse(amount.text) ?? 0,
  );
}

class _RequirementEditor extends StatefulWidget {
  const _RequirementEditor({required this.row, required this.onRemove});
  final _RequirementRow row;
  final VoidCallback onRemove;
  @override
  State<_RequirementEditor> createState() => _RequirementEditorState();
}

class _RequirementEditorState extends State<_RequirementEditor> {
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          TextFormField(
            controller: widget.row.name,
            decoration: const InputDecoration(labelText: 'Requirement name'),
          ),
          TextFormField(
            controller: widget.row.description,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          TextFormField(
            controller: widget.row.extraAllowance,
            decoration: const InputDecoration(labelText: 'Extra allowance INR'),
            keyboardType: TextInputType.number,
          ),
          CheckboxListTile(
            value: widget.row.isMandatory,
            onChanged: (value) =>
                setState(() => widget.row.isMandatory = value ?? true),
            title: const Text('Mandatory'),
          ),
          CheckboxListTile(
            value: widget.row.acknowledgementRequired,
            onChanged: (value) => setState(
              () => widget.row.acknowledgementRequired = value ?? false,
            ),
            title: const Text('Worker acknowledgement required'),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onRemove,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _AllowanceEditor extends StatelessWidget {
  const _AllowanceEditor({required this.row, required this.onRemove});
  final _AllowanceRow row;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          TextFormField(
            controller: row.label,
            decoration: const InputDecoration(labelText: 'Allowance label'),
          ),
          TextFormField(
            controller: row.description,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          TextFormField(
            controller: row.amount,
            decoration: const InputDecoration(labelText: 'Amount INR'),
            keyboardType: TextInputType.number,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove'),
            ),
          ),
        ],
      ),
    ),
  );
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _parseDate(String value) {
  final parts = value.trim().split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  final parsed = DateTime.utc(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day
      ? parsed
      : null;
}

({int hour, int minute})? _parseClock(String value) {
  final match = RegExp(r'^\s*(\d{1,2})(?::(\d{2}))?\s*([AaPp][Mm])?\s*$')
      .firstMatch(value);
  if (match == null) return null;
  var hour = int.parse(match.group(1)!);
  final minute = int.tryParse(match.group(2) ?? '0');
  final suffix = match.group(3)?.toUpperCase();
  if (minute == null || minute > 59) return null;
  if (suffix != null) {
    if (hour < 1 || hour > 12) return null;
    if (suffix == 'AM' && hour == 12) hour = 0;
    if (suffix == 'PM' && hour != 12) hour += 12;
  } else if (hour > 23) {
    return null;
  }
  return (hour: hour, minute: minute);
}

DateTime _combineKolkata(DateTime date, ({int hour, int minute}) clock) =>
    DateTime.utc(
      date.year,
      date.month,
      date.day,
      clock.hour - 5,
      clock.minute - 30,
    );
String _formatDate(DateTime value) {
  final kolkata = value.toUtc().add(const Duration(hours: 5, minutes: 30));
  return '${kolkata.year.toString().padLeft(4, '0')}-${kolkata.month.toString().padLeft(2, '0')}-${kolkata.day.toString().padLeft(2, '0')}';
}

String _formatTime(DateTime value) {
  final kolkata = value.toUtc().add(const Duration(hours: 5, minutes: 30));
  final hour12 = kolkata.hour % 12 == 0 ? 12 : kolkata.hour % 12;
  final minute = kolkata.minute.toString().padLeft(2, '0');
  final suffix = kolkata.hour >= 12 ? 'PM' : 'AM';
  return '$hour12:$minute $suffix';
}
