import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../../../features/auth/application/auth_session.dart';
import '../../../features/auth/domain/phone_number.dart';
import '../../../features/auth/presentation/auth_widgets.dart';
import '../data/worker_repository.dart';
import '../domain/worker_profile.dart';
import '../../../core/widgets/app_feedback.dart';

final workerSearchTextProvider = StateProvider<String>((ref) => '');
final workerDirectoryQueryProvider = StateProvider<WorkerDirectoryQuery>(
  (ref) => const WorkerDirectoryQuery(),
);
final staffDirectoryProvider = FutureProvider<List<StaffProfile>>((ref) {
  return ref.watch(workerRepositoryProvider).searchStaff(limit: 50, offset: 0);
});

final workerDirectoryProvider = FutureProvider<List<WorkerProfile>>((ref) {
  final query = ref.watch(workerDirectoryQueryProvider);
  return ref.watch(workerRepositoryProvider).searchWorkers(query);
});

class WorkerDirectoryScreen extends ConsumerStatefulWidget {
  const WorkerDirectoryScreen({required this.role, super.key});

  final AppRole role;

  @override
  ConsumerState<WorkerDirectoryScreen> createState() =>
      _WorkerDirectoryScreenState();
}

class _WorkerDirectoryScreenState extends ConsumerState<WorkerDirectoryScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workers = ref.watch(workerDirectoryProvider);
    final query = ref.watch(workerDirectoryQueryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Workers')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(staffDirectoryProvider);
            ref.invalidate(workerDirectoryProvider);
            await ref.read(workerDirectoryProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        labelText: 'Search workers',
                        prefixIcon: Icon(Icons.search),
                      ),
                      textInputAction: TextInputAction.search,
                      onChanged: _searchChanged,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        DropdownMenu<AccountStatus?>(
                          key: ValueKey(query.accountStatus),
                          initialSelection: query.accountStatus,
                          label: const Text('Account'),
                          dropdownMenuEntries: [
                            const DropdownMenuEntry(
                              value: null,
                              label: 'All accounts',
                            ),
                            for (final status in AccountStatus.values)
                              DropdownMenuEntry(
                                value: status,
                                label: status.label,
                              ),
                          ],
                          onSelected: (value) => _updateQuery(
                            query.copyWith(
                              accountStatus: value,
                              clearAccountStatus: value == null,
                              offset: 0,
                            ),
                          ),
                        ),
                        DropdownMenu<WorkerCategory?>(
                          key: ValueKey(query.category),
                          initialSelection: query.category,
                          label: const Text('Category'),
                          dropdownMenuEntries: [
                            const DropdownMenuEntry(
                              value: null,
                              label: 'All categories',
                            ),
                            for (final category in WorkerCategory.values)
                              DropdownMenuEntry(
                                value: category,
                                label: category.label,
                              ),
                          ],
                          onSelected: (value) => _updateQuery(
                            query.copyWith(
                              category: value,
                              clearCategory: value == null,
                              offset: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _updateQuery(
                          query.copyWith(
                            accountStatus: AccountStatus.pendingApproval,
                            clearAccountStatus: false,
                            offset: 0,
                          ),
                        ),
                        icon: const Icon(Icons.pending_actions),
                        label: const Text('Pending approvals'),
                      ),
                    ),
                    if (widget.role == AppRole.admin ||
                        widget.role == AppRole.superAdmin)
                      const _StaffPanel(),
                  ],
                ),
              ),
              workers.when(
                data: (items) {
                  if (items.isEmpty) {
                    return AppEmptyState(
                      icon: Icons.people_outline_rounded,
                      title: 'No workers found',
                      message: 'Try another name, phone number or filter.',
                      action: TextButton(
                        onPressed: () {
                          _search.clear();
                          ref.read(workerSearchTextProvider.notifier).state =
                              '';
                          _updateQuery(const WorkerDirectoryQuery());
                        },
                        child: const Text('Clear filters'),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: items.length + 1,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      if (index == items.length) {
                        return _Pager(
                          query: query,
                          hasMore: items.length == query.limit,
                          onQuery: _updateQuery,
                        );
                      }
                      final worker = items[index];
                      return Card(
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          leading: _ProfileAvatar(
                            path: worker.profilePhotoPath,
                          ),
                          title: Text(worker.fullName),
                          subtitle: Text(_workerSubtitle(worker)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go(
                            '${widget.role.homePath}/workers/${worker.userId}',
                          ),
                        ),
                      );
                    },
                  );
                },
                error: (error, stackTrace) => ListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 120),
                    const Center(
                      child: Text('Couldn’t load workers. Please try again.'),
                    ),
                    Center(
                      child: TextButton.icon(
                        onPressed: () =>
                            ref.invalidate(workerDirectoryProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ),
                  ],
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _workerSubtitle(WorkerProfile worker) {
    final category = worker.category?.databaseValue ?? 'No category';
    final requested = worker.requestedCategory == null
        ? ''
        : '  requested ${worker.requestedCategory!.databaseValue}';
    final type = worker.registrationType == null
        ? ''
        : '  ${worker.registrationTypeLabel}';
    return 'ID ${worker.workerNumber ?? '-'}  $category  ${worker.accountStatus.label}$type$requested';
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final trimmed = value.trim();
      ref.read(workerSearchTextProvider.notifier).state = trimmed;
      _updateQuery(
        ref
            .read(workerDirectoryQueryProvider)
            .copyWith(searchText: trimmed.isEmpty ? null : trimmed, offset: 0),
      );
    });
  }

  void _updateQuery(WorkerDirectoryQuery query) {
    ref.read(workerDirectoryQueryProvider.notifier).state = query;
  }
}

class _ProfileAvatar extends ConsumerWidget {
  const _ProfileAvatar({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (path == null) return const CircleAvatar(child: Icon(Icons.person));
    return FutureBuilder<String?>(
      future: ref.read(workerRepositoryProvider).signedProfilePhotoUrl(path),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null) return const CircleAvatar(child: Icon(Icons.person));
        return CircleAvatar(backgroundImage: NetworkImage(url));
      },
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.query,
    required this.hasMore,
    required this.onQuery,
  });

  final WorkerDirectoryQuery query;
  final bool hasMore;
  final ValueChanged<WorkerDirectoryQuery> onQuery;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            onPressed: query.offset == 0
                ? null
                : () => onQuery(
                    query.copyWith(
                      offset: (query.offset - query.limit).clamp(0, 1 << 30),
                    ),
                  ),
            icon: const Icon(Icons.chevron_left),
            label: const Text('Previous'),
          ),
          const SizedBox(width: 16),
          Text('Page ${query.offset ~/ query.limit + 1}'),
          const SizedBox(width: 16),
          TextButton.icon(
            onPressed: hasMore
                ? () => onQuery(
                    query.copyWith(offset: query.offset + query.limit),
                  )
                : null,
            icon: const Icon(Icons.chevron_right),
            label: const Text('Next'),
          ),
        ],
      ),
    );
  }
}

class _StaffPanel extends ConsumerWidget {
  const _StaffPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(staffDirectoryProvider);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Team accounts'),
      trailing: IconButton(
        tooltip: 'Add staff account',
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => const _ProvisionStaffDialog(),
        ),
        icon: const Icon(Icons.person_add_alt),
      ),
      children: [
        staff.when(
          data: (items) {
            if (items.isEmpty) {
              return const ListTile(title: Text('No staff found'));
            }
            return Column(
              children: [
                for (final item in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(child: Icon(Icons.badge)),
                    title: Text(item.fullName),
                    subtitle: Text(
                      '${item.role.label}  ${item.accountStatus.label}  ${item.phoneE164}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Change phone',
                      icon: const Icon(Icons.phone),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) =>
                            _PhoneChangeDialog(userId: item.userId),
                      ),
                    ),
                  ),
              ],
            );
          },
          error: (error, stackTrace) => ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text(friendlyAuthError(error)),
          ),
          loading: () =>
              const ListTile(title: Center(child: CircularProgressIndicator())),
        ),
      ],
    );
  }
}

class _ProvisionStaffDialog extends ConsumerStatefulWidget {
  const _ProvisionStaffDialog();

  @override
  ConsumerState<_ProvisionStaffDialog> createState() =>
      _ProvisionStaffDialogState();
}

class _ProvisionStaffDialogState extends ConsumerState<_ProvisionStaffDialog> {
  final _fullName = TextEditingController();
  final _initials = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _reason = TextEditingController();
  AppRole _role = AppRole.captain;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _initials.dispose();
    _phone.dispose();
    _password.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add staff account'),
      content: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            const Text(
              'Create a team account. They’ll sign in with their WhatsApp number and the password you set.',
            ),
            TextField(
              controller: _fullName,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            TextField(
              controller: _initials,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Initials'),
            ),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'WhatsApp number',
                prefixText: '+91 ',
                hintText: '98765 43210',
              ),
            ),
            PasswordField(controller: _password, label: 'Temporary password'),
            DropdownButtonFormField<AppRole>(
              isExpanded: true,
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: AppRole.admin, child: Text('Admin')),
                DropdownMenuItem(
                  value: AppRole.captain,
                  child: Text('Captain'),
                ),
                DropdownMenuItem(
                  value: AppRole.supervisor,
                  child: Text('Supervisor'),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _role = value ?? _role),
            ),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Creating...' : 'Create'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(workerRepositoryProvider)
          .provisionStaff(
            StaffProvisionRequest(
              fullName: _fullName.text.trim(),
              initials: _initials.text.trim(),
              phoneE164: _phone.text.trim(),
              password: _password.text,
              role: _role,
              reason: _reason.text.trim(),
            ),
          );
      ref.invalidate(staffDirectoryProvider);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _PhoneChangeDialog extends ConsumerStatefulWidget {
  const _PhoneChangeDialog({required this.userId});
  final String userId;

  @override
  ConsumerState<_PhoneChangeDialog> createState() => _PhoneChangeDialogState();
}

class _PhoneChangeDialogState extends ConsumerState<_PhoneChangeDialog> {
  final _phone = TextEditingController();
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change phone'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'New phone'),
            ),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(workerRepositoryProvider)
          .changeUserPhone(
            userId: widget.userId,
            phoneE164: PhoneNumber.parse(_phone.text).value,
            reason: _reason.text.trim(),
          );
      ref.invalidate(staffDirectoryProvider);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
