import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/auth_repository.dart';
import '../domain/phone_number.dart';
import '../domain/worker_registration_input.dart';

class WorkerRegistrationScreen extends ConsumerStatefulWidget {
  const WorkerRegistrationScreen({super.key});

  @override
  ConsumerState<WorkerRegistrationScreen> createState() {
    return _WorkerRegistrationScreenState();
  }
}

class _WorkerRegistrationScreenState
    extends ConsumerState<WorkerRegistrationScreen> {
  final _fullNameController = TextEditingController();
  final _initialsController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _addressController = TextEditingController();
  final _nativePlaceController = TextEditingController();
  final _heightController = TextEditingController();
  final _educationController = TextEditingController();
  final _experienceController = TextEditingController();

  DateTime? _dateOfBirth;
  Uint8List? _profilePhotoBytes;
  String? _profilePhotoMimeType;
  String? _profilePhotoName;
  bool _hasExperience = false;
  bool _isSubmitting = false;
  String? _message;

  @override
  void dispose() {
    _fullNameController.dispose();
    _initialsController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _addressController.dispose();
    _nativePlaceController.dispose();
    _heightController.dispose();
    _educationController.dispose();
    _experienceController.dispose();
    super.dispose();
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (picked == null) {
        return;
      }

      final bytes = await picked.readAsBytes();
      final mimeType = picked.mimeType ?? _mimeTypeFromName(picked.name);

      if (mounted) {
        setState(() {
          _profilePhotoBytes = bytes;
          _profilePhotoMimeType = mimeType;
          _profilePhotoName = picked.name;
          _message = 'Profile photo selected.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _message = 'Profile photo could not be loaded.';
        });
      }
    }
  }

  String _mimeTypeFromName(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.endsWith('.png')) {
      return 'image/png';
    }
    if (lowerName.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  Future<void> _submit() async {
    final dob = _dateOfBirth;
    if (dob == null) {
      setState(() {
        _message = 'Date of birth is required.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _message = null;
    });

    try {
      final photoBytes = _profilePhotoBytes;
      final photoMimeType = _profilePhotoMimeType;
      if (photoBytes == null || photoMimeType == null) {
        throw const FormatException('Profile photo is required.');
      }

      final input = WorkerRegistrationInput(
        fullName: _fullNameController.text,
        initials: _initialsController.text,
        phone: PhoneNumber.parse(_phoneController.text),
        password: _passwordController.text,
        profilePhotoPath: 'pending-client-photo',
        dateOfBirth: dob,
        address: _addressController.text,
        nativePlace: _nativePlaceController.text,
        heightCm: double.parse(_heightController.text),
        educationStatus: _educationController.text,
        hasPreviousExperience: _hasExperience,
        experienceDetails: _experienceController.text,
      );

      await ref
          .read(authRepositoryProvider)
          .registerWorker(
            input: input,
            profilePhotoBytes: photoBytes,
            profilePhotoMimeType: photoMimeType,
          );

      if (mounted) {
        setState(() {
          _message = 'Registration submitted.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _message = 'Registration could not be completed.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Worker registration')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _fullNameController,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _initialsController,
              decoration: const InputDecoration(labelText: 'Initials'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isSubmitting ? null : _pickProfilePhoto,
              icon: const Icon(Icons.photo),
              label: Text(
                _profilePhotoName == null
                    ? 'Choose profile photo'
                    : 'Photo selected',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(now.year - 80),
                  lastDate: now,
                  initialDate: DateTime(now.year - 18),
                );
                if (picked != null && mounted) {
                  setState(() => _dateOfBirth = picked);
                }
              },
              child: Text(
                _dateOfBirth == null
                    ? 'Select date of birth'
                    : _dateOfBirth!.toIso8601String().split('T').first,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nativePlaceController,
              decoration: const InputDecoration(labelText: 'Native place'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _heightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Height in cm'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _educationController,
              decoration: const InputDecoration(labelText: 'Education status'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _hasExperience,
              onChanged: (value) => setState(() => _hasExperience = value),
              title: const Text('Previous experience'),
            ),
            TextField(
              controller: _experienceController,
              decoration: const InputDecoration(
                labelText: 'Experience details',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: Text(_isSubmitting ? 'Registering' : 'Register'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!),
            ],
          ],
        ),
      ),
    );
  }
}
