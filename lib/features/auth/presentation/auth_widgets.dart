import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_failure.dart';

String friendlyAuthError(Object error) {
  if (error is FormatException) return error.message;
  if (error is AuthFailure) return error.message;
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
