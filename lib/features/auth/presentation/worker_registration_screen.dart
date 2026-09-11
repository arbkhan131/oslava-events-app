import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../application/auth_session.dart';
import '../application/logout.dart';
import '../data/auth_repository.dart';
import '../data/profile_photo_preparer.dart';
import '../domain/phone_number.dart';
import '../domain/worker_registration_input.dart';
import 'auth_widgets.dart';

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
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _placeController = TextEditingController();
  final _heightController = TextEditingController();
  final _educationController = TextEditingController();

  WorkerRegistrationType _registrationType = WorkerRegistrationType.newWorker;
  WorkerExperienceLevel _experienceLevel = WorkerExperienceLevel.noExperience;
  RegistrationWorkerCategory? _requestedCategory;
  DateTime? _dateOfBirth;
  Uint8List? _profilePhotoBytes;
  String? _profilePhotoMimeType;
  String? _profilePhotoName;
  Uint8List? _idCardBytes;
  String? _idCardName;
  String _idCardMimeType = 'application/octet-stream';
  bool _acceptedPrivacyTerms = false;
  bool _isSubmitting = false;
  String? _message;
  Map<String, dynamic>? _terms;

  @override
  void initState() {
    super.initState();
    _restoreDraft();
    Future.microtask(_loadTerms);
  }

  void _restoreDraft() {
    final repository = ref.read(authRepositoryProvider);
    final draft = repository.registrationDraft;
    _phoneController.text =
        repository.registrationPhone ??
        draft['phone_e164']?.toString() ??
        _phoneController.text;
    _fullNameController.text =
        draft['full_name']?.toString() ?? _fullNameController.text;
    _placeController.text =
        draft['native_place']?.toString() ?? _placeController.text;
    _heightController.text =
        draft['height_cm']?.toString() ?? _heightController.text;
    _educationController.text =
        draft['education_status']?.toString() ?? _educationController.text;
    _dateOfBirth =
        DateTime.tryParse(draft['date_of_birth']?.toString() ?? '') ??
        _dateOfBirth;
    _registrationType = draft['registration_type'] == 'OLD_WORKER'
        ? WorkerRegistrationType.oldWorker
        : _registrationType;
    _experienceLevel = switch (draft['experience_level']) {
      'SOME_EXPERIENCE' => WorkerExperienceLevel.someExperience,
      'HIGHLY_EXPERIENCED' => WorkerExperienceLevel.highlyExperienced,
      _ => _experienceLevel,
    };
    _requestedCategory = switch (draft['p_requested_category']) {
      'A' => RegistrationWorkerCategory.a,
      'B' => RegistrationWorkerCategory.b,
      'C' => RegistrationWorkerCategory.c,
      'F' => RegistrationWorkerCategory.f,
      _ => _requestedCategory,
    };
  }

  Future<void> _loadTerms() async {
    try {
      final terms = await ref.read(authRepositoryProvider).loadPrivacyTerms();
      if (mounted) {
        setState(() {
          _terms = terms;
          _acceptedPrivacyTerms = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _message = 'Could not load the terms. Retry before registering.',
        );
      }
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _placeController.dispose();
    _heightController.dispose();
    _educationController.dispose();
    super.dispose();
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final mimeType = picked.mimeType ?? _imageMimeTypeFromName(picked.name);
      final prepared = const ProfilePhotoPreparer().prepare(
        userId: 'preview',
        sourceBytes: bytes,
        mimeType: mimeType,
      );

      if (mounted) {
        setState(() {
          _profilePhotoBytes = prepared.bytes;
          _profilePhotoMimeType = prepared.mimeType;
          _profilePhotoName = picked.name;
          _message = 'Passport size photo selected.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = friendlyAuthError(e));
    }
  }

  Future<void> _pickIdCard() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      final bytes = file == null ? null : await file.readAsBytes();
      if (file == null || bytes == null) return;
      if (mounted) {
        setState(() {
          _idCardBytes = bytes;
          _idCardName = file.name;
          _idCardMimeType = _idMimeTypeFromName(file.name);
          _message = 'ID card selected.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = friendlyAuthError(e));
    }
  }

  String _imageMimeTypeFromName(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.endsWith('.png')) return 'image/png';
    if (lowerName.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  String _idMimeTypeFromName(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.endsWith('.pdf')) return 'application/pdf';
    if (lowerName.endsWith('.png')) return 'image/png';
    if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lowerName.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }

  int? _age() {
    final dob = _dateOfBirth;
    if (dob == null) return null;
    return WorkerRegistrationInput(
      registrationType: WorkerRegistrationType.newWorker,
      fullName: 'preview',
      phone: PhoneNumber.parse('9999999999'),
      password: 'preview',
      profilePhotoPath: 'preview',
      idCardFilePath: 'preview',
      dateOfBirth: dob,
      place: 'preview',
      heightCm: 1,
      educationStatus: 'preview',
      experienceLevel: WorkerExperienceLevel.noExperience,
      privacyTermsVersion: 'preview',
    ).completeYearsAt(DateTime.now());
  }

  Future<void> _submit() async {
    if (_isSubmitting || _terms == null) return;
    final dob = _dateOfBirth;
    if (!_acceptedPrivacyTerms) {
      setState(() {
        _message = 'Privacy Notice and Terms acknowledgement is required.';
      });
      return;
    }
    if (dob == null) {
      setState(() => _message = 'Date of birth is required.');
      return;
    }
    if (_profilePhotoBytes == null || _profilePhotoMimeType == null) {
      setState(() => _message = 'Passport size photo is required.');
      return;
    }
    if (_idCardBytes == null || _idCardName == null) {
      setState(() => _message = 'ID card file is required.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _message = null;
    });
    final controller = ref.read(authSessionControllerProvider);
    controller.setAuthFlowInProgress(true);

    try {
      final input = WorkerRegistrationInput(
        registrationType: _registrationType,
        fullName: _fullNameController.text,
        phone: PhoneNumber.parse(_phoneController.text),
        password: _passwordController.text,
        profilePhotoPath: 'pending-client-photo',
        idCardFilePath: 'pending-client-id-card',
        dateOfBirth: dob,
        place: _placeController.text,
        heightCm: double.parse(_heightController.text),
        educationStatus: _educationController.text,
        experienceLevel: _experienceLevel,
        requestedCategory: _registrationType == WorkerRegistrationType.oldWorker
            ? _requestedCategory
            : null,
        privacyTermsVersion: _terms!['version'] as String,
      );

      final session = await ref
          .read(authRepositoryProvider)
          .registerWorker(
            input: input,
            profilePhotoBytes: _profilePhotoBytes!,
            profilePhotoMimeType: _profilePhotoMimeType!,
            idCardBytes: _idCardBytes!,
            idCardFileName: _idCardName!,
            idCardMimeType: _idCardMimeType,
          );

      controller.setSession(session);
      if (mounted) {
        context.go(session.isRestricted ? '/session' : session.role.homePath);
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e) {
      if (mounted) setState(() => _message = friendlyAuthError(e));
    } finally {
      controller.setAuthFlowInProgress(false);
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 80),
      lastDate: now,
      initialDate: _dateOfBirth ?? DateTime(now.year - 18, now.month, now.day),
    );
    if (picked != null && mounted) setState(() => _dateOfBirth = picked);
  }

  @override
  Widget build(BuildContext context) {
    final age = _age();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Worker registration'),
        leading: BackButton(
          onPressed: () async {
            if (_isSubmitting) return;
            try {
              await logout(ref);
              if (context.mounted) context.go('/login');
            } catch (_) {
              if (mounted) {
                setState(() => _message = 'Could not sign out. Please retry.');
              }
            }
          },
        ),
      ),
      body: AuthFormBody(
        children: [
          SegmentedButton<WorkerRegistrationType>(
            segments: const [
              ButtonSegment(
                value: WorkerRegistrationType.newWorker,
                label: Text('New worker'),
              ),
              ButtonSegment(
                value: WorkerRegistrationType.oldWorker,
                label: Text('Old worker'),
              ),
            ],
            selected: {_registrationType},
            onSelectionChanged: _isSubmitting
                ? null
                : (value) {
                    setState(() {
                      _registrationType = value.single;
                      if (_registrationType ==
                          WorkerRegistrationType.newWorker) {
                        _requestedCategory = null;
                      }
                    });
                  },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _fullNameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Name with initial',
              hintText: 'Muhammed Siyas K C',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _placeController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Place'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 +()-]')),
            ],
            decoration: const InputDecoration(
              labelText: 'WhatsApp number',
              prefixText: '+91 ',
              hintText: '98765 43210',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _heightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Height in cm'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _educationController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Studying class',
              hintText: '12th class or BSc Physics',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<WorkerExperienceLevel>(
            initialValue: _experienceLevel,
            decoration: const InputDecoration(labelText: 'Work experience'),
            items: WorkerExperienceLevel.values
                .map(
                  (level) =>
                      DropdownMenuItem(value: level, child: Text(level.label)),
                )
                .toList(),
            onChanged: _isSubmitting
                ? null
                : (value) => setState(() => _experienceLevel = value!),
          ),
          if (_registrationType == WorkerRegistrationType.oldWorker) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<RegistrationWorkerCategory>(
              initialValue: _requestedCategory,
              decoration: const InputDecoration(
                labelText: 'Old worker category',
              ),
              items: RegistrationWorkerCategory.values
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category.label),
                    ),
                  )
                  .toList(),
              onChanged: _isSubmitting
                  ? null
                  : (value) => setState(() => _requestedCategory = value),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _isSubmitting ? null : _pickDob,
            child: Text(
              _dateOfBirth == null
                  ? 'Select date of birth'
                  : 'Date of birth: ${_dateOfBirth!.toIso8601String().split('T').first} (${age ?? 0} years)',
            ),
          ),
          const SizedBox(height: 12),
          PasswordField(
            controller: _passwordController,
            label: 'Create password',
          ),
          const SizedBox(height: 16),
          if (_profilePhotoBytes != null)
            Image.memory(
              _profilePhotoBytes!,
              height: 120,
              semanticLabel: 'Selected passport size photo',
            ),
          OutlinedButton.icon(
            onPressed: _isSubmitting ? null : _pickProfilePhoto,
            icon: const Icon(Icons.photo),
            label: Text(
              _profilePhotoName == null
                  ? 'Upload passport size photo'
                  : 'Passport photo selected',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isSubmitting ? null : _pickIdCard,
            icon: const Icon(Icons.badge_outlined),
            label: Text(_idCardName == null ? 'Upload ID card' : _idCardName!),
          ),
          CheckboxListTile(
            value: _acceptedPrivacyTerms,
            onChanged: _isSubmitting
                ? null
                : (value) =>
                      setState(() => _acceptedPrivacyTerms = value ?? false),
            title: Text(
              'I accept the Privacy Notice and Terms ${_terms?['version'] ?? ''}',
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          TextButton(
            onPressed: _terms == null
                ? _loadTerms
                : () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(
                        'Privacy Notice and Terms ${_terms!['version']}',
                      ),
                      content: SingleChildScrollView(
                        child: SelectableText(_terms!['summary'] as String),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
            child: Text(
              _terms == null
                  ? 'Retry loading terms'
                  : 'Read Privacy Notice and Terms',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _isSubmitting || _terms == null ? null : _submit,
            child: Text(_isSubmitting ? 'Registering…' : 'Submit registration'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!),
          ],
        ],
      ),
    );
  }
}
