import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/worker_repository.dart';
import '../domain/worker_profile.dart';
import 'worker_profile_screen.dart';

class EditWorkerProfileScreen extends ConsumerStatefulWidget {
  const EditWorkerProfileScreen({super.key});

  @override
  ConsumerState<EditWorkerProfileScreen> createState() =>
      _EditWorkerProfileScreenState();
}

class _EditWorkerProfileScreenState
    extends ConsumerState<EditWorkerProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _initials = TextEditingController();
  final _address = TextEditingController();
  final _nativePlace = TextEditingController();
  final _height = TextEditingController();
  final _education = TextEditingController();
  final _experienceDetails = TextEditingController();
  bool _hasPreviousExperience = false;
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _fullName.dispose();
    _initials.dispose();
    _address.dispose();
    _nativePlace.dispose();
    _height.dispose();
    _education.dispose();
    _experienceDetails.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(ownWorkerProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: profile.when(
          data: (worker) {
            _loadOnce(worker);
            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _fullName,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: _required,
                  ),
                  TextFormField(
                    controller: _initials,
                    decoration: const InputDecoration(labelText: 'Initials'),
                    validator: _required,
                  ),
                  TextFormField(
                    controller: _address,
                    decoration: const InputDecoration(labelText: 'Address'),
                    validator: _required,
                  ),
                  TextFormField(
                    controller: _nativePlace,
                    decoration: const InputDecoration(
                      labelText: 'Native place',
                    ),
                    validator: _required,
                  ),
                  TextFormField(
                    controller: _height,
                    decoration: const InputDecoration(labelText: 'Height cm'),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed <= 0) {
                        return 'Enter a valid height.';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _education,
                    decoration: const InputDecoration(
                      labelText: 'Education status',
                    ),
                    validator: _required,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Previous event experience'),
                    value: _hasPreviousExperience,
                    onChanged: _saving
                        ? null
                        : (value) =>
                              setState(() => _hasPreviousExperience = value),
                  ),
                  TextFormField(
                    controller: _experienceDetails,
                    decoration: const InputDecoration(
                      labelText: 'Experience details',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _save(worker),
                    icon: const Icon(Icons.save),
                    label: Text(_saving ? 'Saving...' : 'Save'),
                  ),
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

  void _loadOnce(WorkerProfile worker) {
    if (_loaded) {
      return;
    }
    _loaded = true;
    _fullName.text = worker.fullName;
    _initials.text = worker.initials;
    _address.text = worker.address ?? '';
    _nativePlace.text = worker.nativePlace ?? '';
    _height.text = worker.heightCm?.toString() ?? '';
    _education.text = worker.educationStatus ?? '';
    _hasPreviousExperience = worker.hasPreviousExperience ?? false;
    _experienceDetails.text = worker.experienceDetails ?? '';
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required.';
    }
    return null;
  }

  Future<void> _save(WorkerProfile worker) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(workerRepositoryProvider)
          .updateOwnProfile(
            WorkerProfileUpdate(
              fullName: _fullName.text,
              initials: _initials.text,
              address: _address.text,
              nativePlace: _nativePlace.text,
              heightCm: double.parse(_height.text),
              educationStatus: _education.text,
              hasPreviousExperience: _hasPreviousExperience,
              experienceDetails: _experienceDetails.text,
              profilePhotoPath: worker.profilePhotoPath,
            ),
          );
      ref.invalidate(ownWorkerProfileProvider);
      if (mounted) {
        context.go('/worker/profile');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
