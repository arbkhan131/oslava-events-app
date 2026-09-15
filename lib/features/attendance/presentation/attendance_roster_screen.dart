import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_feedback.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../events/domain/event_summary.dart';
import '../../workers/domain/worker_profile.dart';
import '../../performance/domain/performance_review.dart';
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
            final counters = items.isEmpty
                ? AttendanceCounters.fromRoster(items)
                : items.first.fullCounters ??
                      AttendanceCounters.fromRoster(items);
            final filtered = items.isEmpty
                ? 0
                : items.first.filteredCount ?? items.length;

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
                      helperText: 'Name, phone, Worker ID or category',
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
                  _Counters(counters: counters, filtered: filtered),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => context.go(
                        '${widget.basePath}/events/${widget.eventId}/report',
                      ),
                      icon: const Icon(Icons.summarize),
                      label: const Text('Report'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 64),
                      child: Center(child: Text('No matching workers')),
                    )
                  else
                    for (final group in _groupByCategory(items)) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Text(
                          'Category ${group.category.databaseValue}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      for (final entry in group.items)
                        _RosterTile(
                          entry: entry,
                          photoUrl: ref
                              .watch(
                                _signedRosterPhotoProvider(
                                  entry.profilePhotoPath,
                                ),
                              )
                              .maybeWhen(
                                data: (url) => url,
                                orElse: () => null,
                              ),
                          onStatusChanged: (status) =>
                              _markAttendance(entry, status),
                          onReview: () => _recordReview(entry),
                        ),
                    ],
                ],
              ),
            );
          },
          error: (error, stackTrace) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AppEmptyState(
                icon: Icons.assignment_late_outlined,
                title: 'Could not load attendance',
                message: friendlyAuthError(error),
                action: OutlinedButton.icon(
                  onPressed: () =>
                      ref.invalidate(attendanceRosterProvider(query)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
            ),
          ),
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
          .showSnackBar(SnackBar(content: Text(friendlyAuthError(error))));
    }
  }

  Future<void> _recordReview(AttendanceRosterEntry entry) async {
    final input = await showDialog<PerformanceReviewInput>(
      context: context,
      builder: (context) => _PerformanceReviewDialog(entry: entry),
    );
    if (input == null) {
      return;
    }

    try {
      await ref
          .read(attendanceRepositoryProvider)
          .recordPerformanceReview(input);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Performance review saved')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyAuthError(error))));
    }
  }
}

class _Counters extends StatelessWidget {
  const _Counters({required this.counters, required this.filtered});

  final AttendanceCounters counters;
  final int filtered;

  @override
  Widget build(BuildContext context) {
    final values = [
      ('Total', counters.total),
      ('Showing', filtered),
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

final _signedRosterPhotoProvider = FutureProvider.autoDispose
    .family<String?, String?>(
      (ref, storagePath) => ref
          .watch(attendanceRepositoryProvider)
          .signedProfilePhotoUrl(storagePath),
    );

class _RosterGroup {
  const _RosterGroup({required this.category, required this.items});
  final WorkerCategory category;
  final List<AttendanceRosterEntry> items;
}

List<_RosterGroup> _groupByCategory(List<AttendanceRosterEntry> items) {
  final grouped = <WorkerCategory, List<AttendanceRosterEntry>>{};
  for (final item in items) {
    grouped.putIfAbsent(item.categoryAtConfirmation, () => []).add(item);
  }
  return grouped.entries
      .map((entry) => _RosterGroup(category: entry.key, items: entry.value))
      .toList(growable: false);
}

class _RosterTile extends StatelessWidget {
  const _RosterTile({
    required this.entry,
    required this.photoUrl,
    required this.onStatusChanged,
    required this.onReview,
  });

  final AttendanceRosterEntry entry;
  final String? photoUrl;
  final ValueChanged<AttendanceStatus> onStatusChanged;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundImage: photoUrl == null ? null : NetworkImage(photoUrl!),
        child: photoUrl == null
            ? Text(entry.categoryAtConfirmation.databaseValue)
            : null,
      ),
      title: Text(entry.fullName),
      subtitle: Text(
        [
          if (entry.workerNumber != null) '#${entry.workerNumber}',
          entry.phoneE164,
          entry.attendanceStatus.label,
          if (entry.markedAt != null) formatKolkataDateTime12h(entry.markedAt!),
          if (entry.notes != null) entry.notes!,
          if (entry.reviewStars != null) 'Review ${entry.reviewStars}★',
        ].join('  '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: entry.reviewId == null
                ? 'Review performance'
                : 'Edit performance review',
            onPressed: onReview,
            icon: const Icon(Icons.star_rate),
          ),
          DropdownButton<AttendanceStatus>(
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
        ],
      ),
    );
  }
}

class _PerformanceReviewDialog extends StatefulWidget {
  const _PerformanceReviewDialog({required this.entry});

  final AttendanceRosterEntry entry;

  @override
  State<_PerformanceReviewDialog> createState() =>
      _PerformanceReviewDialogState();
}

class _PerformanceReviewDialogState extends State<_PerformanceReviewDialog> {
  final _tags = TextEditingController();
  final _notes = TextEditingController();
  late int _stars;

  @override
  void initState() {
    super.initState();
    _stars = widget.entry.reviewStars ?? 5;
    _tags.text = widget.entry.reviewTags.join(', ');
    _notes.text = widget.entry.reviewNotes ?? '';
  }

  @override
  void dispose() {
    _tags.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.entry.reviewId == null
            ? 'Performance review'
            : 'Edit performance review',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _stars,
              decoration: const InputDecoration(labelText: 'Stars'),
              items: [
                for (var value = 1; value <= 5; value += 1)
                  DropdownMenuItem(value: value, child: Text('$value')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _stars = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Tags',
                hintText: 'punctual, professional',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              PerformanceReviewInput(
                assignmentId: widget.entry.assignmentId,
                stars: _stars,
                tags: _tags.text
                    .split(',')
                    .map((tag) => tag.trim())
                    .where((tag) => tag.isNotEmpty)
                    .toList(growable: false),
                notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
