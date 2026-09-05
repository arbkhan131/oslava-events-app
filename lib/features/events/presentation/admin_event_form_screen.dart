import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/event_repository.dart';
import '../domain/event_summary.dart';
import 'admin_event_list_screen.dart';

class AdminEventFormScreen extends ConsumerStatefulWidget {
  const AdminEventFormScreen({required this.basePath, super.key});

  final String basePath;

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
  final _workers = TextEditingController(text: '10');
  final _wage = TextEditingController(text: '1200');
  final _tierA = TextEditingController(text: '0');
  final _tierB = TextEditingController(text: '30');
  final _tierC = TextEditingController(text: '60');
  final _tierF = TextEditingController(text: '180');
  final _instructions = TextEditingController();
  final _dressCode = TextEditingController();
  TierStrategy _tierStrategy = TierStrategy.standard;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _eventType.dispose();
    _venue.dispose();
    _mapsUrl.dispose();
    _workers.dispose();
    _wage.dispose();
    _tierA.dispose();
    _tierB.dispose();
    _tierC.dispose();
    _tierF.dispose();
    _instructions.dispose();
    _dressCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New event')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
                decoration: const InputDecoration(labelText: 'Maps URL'),
              ),
              TextFormField(
                controller: _workers,
                decoration: const InputDecoration(labelText: 'Workers needed'),
                keyboardType: TextInputType.number,
                validator: _positiveInt,
              ),
              TextFormField(
                controller: _wage,
                decoration: const InputDecoration(labelText: 'Daily wage INR'),
                keyboardType: TextInputType.number,
                validator: _nonNegativeMoney,
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
                    : (value) {
                        final next = value ?? TierStrategy.standard;
                        setState(() {
                          _tierStrategy = next;
                          if (next != TierStrategy.custom) {
                            _applyPresetOffsets(next);
                          }
                        });
                      },
              ),
              if (_tierStrategy == TierStrategy.custom) ...[
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
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    describeTierReleaseOffsets(
                      TierReleaseOffsets.presetFor(_tierStrategy),
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
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
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(_saving ? 'Saving...' : 'Save draft'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required.';
    }
    return null;
  }

  String? _positiveInt(String? value) {
    final parsed = int.tryParse(value ?? '');
    if (parsed == null || parsed <= 0) {
      return 'Enter a positive number.';
    }
    return null;
  }

  String? _nonNegativeMoney(String? value) {
    final parsed = double.tryParse(value ?? '');
    if (parsed == null || parsed < 0) {
      return 'Enter zero or more.';
    }
    return null;
  }

  String? _nonNegativeInt(String? value) {
    final parsed = int.tryParse(value ?? '');
    if (parsed == null || parsed < 0) {
      return 'Enter zero or more.';
    }
    return null;
  }

  void _applyPresetOffsets(TierStrategy strategy) {
    final offsets = TierReleaseOffsets.presetFor(strategy);
    _tierA.text = offsets.aMinutes.toString();
    _tierB.text = offsets.bMinutes.toString();
    _tierC.text = offsets.cMinutes.toString();
    _tierF.text = offsets.fMinutes.toString();
  }

  TierReleaseOffsets _customOffsetsFromForm() {
    return TierReleaseOffsets(
      aMinutes: int.parse(_tierA.text),
      bMinutes: int.parse(_tierB.text),
      cMinutes: int.parse(_tierC.text),
      fMinutes: int.parse(_tierF.text),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final customOffsets = _tierStrategy == TierStrategy.custom
        ? _customOffsetsFromForm()
        : null;

    if (customOffsets != null && !customOffsets.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tier release offsets must expand in A, B, C, F order.',
          ),
        ),
      );
      return;
    }

    final now = DateTime.now().toUtc().add(const Duration(days: 7));
    final reportingAt = DateTime.utc(now.year, now.month, now.day, 9);

    setState(() => _saving = true);
    try {
      await ref
          .read(eventRepositoryProvider)
          .createDraft(
            EventDraftInput(
              title: _title.text,
              eventType: _eventType.text,
              venueName: _venue.text,
              mapsUrl: _mapsUrl.text,
              reportingAt: reportingAt,
              workStartsAt: reportingAt.add(const Duration(hours: 1)),
              expectedEndsAt: reportingAt.add(const Duration(hours: 9)),
              requiredWorkerCount: int.parse(_workers.text),
              dailyWage: double.parse(_wage.text),
              tierStrategy: _tierStrategy,
              customTierOffsets: customOffsets,
              instructions: _instructions.text,
              dressCode: _dressCode.text,
            ),
          );
      ref.invalidate(adminEventsProvider);
      if (mounted) {
        context.go('${widget.basePath}/events');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
