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
                    : (value) => setState(
                        () => _tierStrategy = value ?? TierStrategy.standard,
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
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
