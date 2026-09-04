import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap.dart';
import '../data/auth_repository.dart';
import '../domain/phone_number.dart';

class PasswordRecoveryScreen extends ConsumerStatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  ConsumerState<PasswordRecoveryScreen> createState() {
    return _PasswordRecoveryScreenState();
  }
}

class _PasswordRecoveryScreenState
    extends ConsumerState<PasswordRecoveryScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  bool _otpSent = false;
  bool _isSubmitting = false;
  String? _message;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _startRecovery() async {
    setState(() {
      _isSubmitting = true;
      _message = null;
    });

    try {
      final environment = ref.read(appEnvironmentProvider);
      await ref
          .read(authRepositoryProvider)
          .startPasswordRecovery(
            phone: PhoneNumber.parse(_phoneController.text),
            environmentName: environment.name.name,
          );

      if (mounted) {
        setState(() {
          _otpSent = true;
          _message = 'OTP sent to the registered phone number.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _message = 'Unable to start password recovery.';
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

  Future<void> _finishRecovery() async {
    setState(() {
      _isSubmitting = true;
      _message = null;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .verifyRecoveryOtpAndSetPassword(
            phone: PhoneNumber.parse(_phoneController.text),
            otp: _otpController.text,
            newPassword: _newPasswordController.text,
          );

      if (mounted) {
        setState(() {
          _message = 'Password updated.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _message = 'Unable to verify OTP or update password.';
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
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                    ),
                  ),
                  if (_otpSent) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'OTP'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New password',
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _isSubmitting
                        ? null
                        : _otpSent
                        ? _finishRecovery
                        : _startRecovery,
                    child: Text(_otpSent ? 'Update password' : 'Send OTP'),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
