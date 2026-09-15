import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_failure.dart';

String friendlyAuthError(Object error) {
  if (error is FormatException) return error.message;
  if (error is AuthFailure) return error.message;
  if (error is TimeoutException) {
    return 'The server is taking too long to respond. Please retry.';
  }
  if (error is StorageException) {
    final message = error.message.trim();
    if (message.isNotEmpty) {
      return 'Document upload failed: $message';
    }
    return 'Document upload failed. Please choose the files again and retry.';
  }
  if (error is PostgrestException) {
    final message = _readableSupabaseMessage(error.message);
    if (_isMissingBackendFunction(message)) {
      return 'This feature is not ready on the server yet. Ask the admin to apply the latest Supabase update and retry.';
    }
    if (message.isNotEmpty) return message;
    return 'Registration could not be saved. Please retry.';
  }
  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    if (details is String && details.trim().isNotEmpty) {
      return details;
    }
    if (error.status == 0) {
      return 'Could not reach registration server. Check your connection and try again.';
    }
    return 'Registration server returned an error. Please retry.';
  }
  if (error is AuthException) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'WhatsApp number or password is incorrect.';
      case 'user_already_exists':
      case 'phone_exists':
        return 'This WhatsApp number is already registered. Sign in to continue.';
      case 'otp_expired':
        return 'The code is invalid or expired. Request a new code.';
      case 'over_sms_send_rate_limit':
      case 'over_request_rate_limit':
        return 'Please wait before requesting another code.';
      case 'weak_password':
        return 'Choose a stronger password with at least six characters.';
      case 'phone_provider_disabled':
        return 'Phone login is not enabled on the staging server. Ask the admin to enable phone auth in Supabase.';
    }
    if (error.message.toLowerCase().contains('phone logins are disabled')) {
      return 'Phone login is not enabled on the staging server. Ask the admin to enable phone auth in Supabase.';
    }
    return error.message;
  }
  return 'We could not complete that request. Check your connection and try again.';
}

bool _isMissingBackendFunction(String message) {
  final lower = message.toLowerCase();
  return lower.contains('could not find the function') &&
      lower.contains('schema cache');
}

String _readableSupabaseMessage(String rawMessage) {
  final message = rawMessage.trim();
  if (message.isEmpty) return '';
  try {
    final decoded = jsonDecode(message);
    if (decoded is Map) {
      final readable = decoded['message'] ?? decoded['error'] ?? decoded['msg'];
      if (readable is String && readable.trim().isNotEmpty) {
        return readable.trim();
      }
    }
  } catch (_) {}
  return message;
}

class AuthFormBody extends StatelessWidget {
  const AuthFormBody({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    ),
  );
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    required this.controller,
    this.label = 'Password',
    this.onSubmitted,
    super.key,
  });
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onSubmitted;
  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool hidden = true;
  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    obscureText: hidden,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: [
      widget.label == 'Password'
          ? AutofillHints.password
          : AutofillHints.newPassword,
    ],
    textInputAction: widget.onSubmitted == null
        ? TextInputAction.next
        : TextInputAction.done,
    onSubmitted: widget.onSubmitted,
    decoration: InputDecoration(
      labelText: widget.label,
      suffixIcon: IconButton(
        tooltip: hidden ? 'Show password' : 'Hide password',
        onPressed: () => setState(() => hidden = !hidden),
        icon: Icon(hidden ? Icons.visibility : Icons.visibility_off),
      ),
    ),
  );
}
