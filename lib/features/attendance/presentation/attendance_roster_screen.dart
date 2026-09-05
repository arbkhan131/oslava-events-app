import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../events/domain/event_summary.dart';
import '../data/attendance_repository.dart';
import '../domain/attendance_roster.dart';

final attendanceRosterProvider = FutureProvider.autoDispose
    .family<List<AttendanceRosterEntry>, AttendanceRosterQuery>(
      (ref, query) => ref
          .watch(attendanceRepositoryProvider)
          .loadRoster(eventId: query.eventId, searchText: query.searchText),
    );

class AttendanceRosterQuery {
  const AttendanceRosterQuery({required this.eventId, this.searchText});

  final String eventId;
  final String? searchText;

  @override
  bool operator ==(Object other) {
    return other is AttendanceRosterQuery &&
        other.eventId == eventId &&
        other.searchText == searchText;
  }

  @override
  int get hashCode => Object.hash(eventId, searchText);
}

class AttendanceRosterScreen extends ConsumerStatefulWidget {
  const AttendanceRosterScreen({
    required this.eventId,
    required this.basePath,
    super.key,
  });

  final String eventId;
  final String basePath;

  @override
  ConsumerState<AttendanceRosterScreen> createState() =>
      _AttendanceRosterScreenState();
}

class _AttendanceRosterScreenState
    extends ConsumerState<AttendanceRosterScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _searchText = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = AttendanceRosterQuery(
      eventId: widget.eventId,
      searchText: _searchText.trim().isEmpty ? null : _searchText.trim(),
    );
    final roster = ref.watch(attendanceRosterProvider(query));

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: SafeArea(
        child: roster.when(
          data: (items) {
            final counters = AttendanceCounters.fromRoster(items);

            return RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(attendanceRosterProvider(query)),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search workers',
                    ),
                    onChanged: (value) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 250), () {
                        if (mounted) {
                          setState(() => _searchText = value);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _Counters(counters: counters),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 64),
                      child: Center(child: Text('No confirmed workers')),
                    )
                  else
                    for (final entry in items) ...[
                      _RosterTile(
                        entry: entry,
                        onStatusChanged: (status) =>
                            _markAttendance(entry, status),
                      ),
                      const Divider(height: 1),
                    ],
                ],
              ),
            );
          },
          error: (error, stackTrace) => Center(child: Text(error.toString())),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Future<void> _markAttendance(
    AttendanceRosterEntry entry,
    AttendanceStatus status,
  ) async {
    try {
      await ref
          .read(attendanceRepositoryProvider)
          .setAttendance(assignmentId: entry.assignmentId, status: status);
      ref.invalidate(
        attendanceRosterProvider(
          AttendanceRosterQuery(
            eventId: widget.eventId,
            searchText: _searchText.trim().isEmpty ? null : _searchText.trim(),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _Counters extends StatelessWidget {
  const _Counters({required this.counters});

  final AttendanceCounters counters;

  @override
  Widget build(BuildContext context) {
    final values = [
      ('Total', counters.total),
      ('Open', counters.notMarked),
      ('Present', counters.present),
      ('Late', counters.late),
      ('Absent', counters.absent),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          Chip(
            label: Text('${value.$1} ${value.$2}'),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class _RosterTile extends StatelessWidget {
  const _RosterTile({required this.entry, required this.onStatusChanged});

  final AttendanceRosterEntry entry;
  final ValueChanged<AttendanceStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Text(entry.categoryAtConfirmation.databaseValue),
      ),
      title: Text(entry.fullName),
      subtitle: Text(
        [
          if (entry.workerNumber != null) '#${entry.workerNumber}',
          entry.phoneE164,
          entry.attendanceStatus.label,
          if (entry.markedAt != null) formatKolkataDateTime12h(entry.markedAt!),
        ].join('  '),
      ),
      trailing: DropdownButton<AttendanceStatus>(
        value: entry.attendanceStatus,
        onChanged: (status) {
          if (status != null) {
            onStatusChanged(status);
          }
        },
        items: [
          for (final status in AttendanceStatus.values)
            DropdownMenuItem(value: status, child: Text(status.label)),
        ],
      ),
    );
  }
}
