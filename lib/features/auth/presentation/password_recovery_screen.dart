import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';
import '../domain/email_address.dart';
import 'auth_widgets.dart';

class PasswordRecoveryScreen extends ConsumerStatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  ConsumerState<PasswordRecoveryScreen> createState() =>
      _PasswordRecoveryState();
}

class _PasswordRecoveryState extends ConsumerState<PasswordRecoveryScreen> {
  final email = TextEditingController();
  bool sent = false, busy = false;
  int cooldown = 0;
  String? message;
  Timer? timer;

  @override
  void dispose() {
    timer?.cancel();
    email.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy || cooldown > 0) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .startPasswordRecovery(
            email: EmailAddress.parse(email.text),
            environmentName: 'staging',
          );
      if (!mounted) return;
      setState(() {
        sent = true;
        cooldown = 30;
        message = 'Password reset email sent. Open the link from your email to set a new password.';
      });
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || cooldown <= 1) {
          t.cancel();
          if (mounted) setState(() => cooldown = 0);
        } else {
          setState(() => cooldown--);
        }
      });
    } catch (e) {
      if (mounted) setState(() => message = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Reset password'),
      leading: BackButton(onPressed: () => context.go('/login')),
    ),
    body: AuthFormBody(
      children: [
        TextField(
          controller: email,
          readOnly: sent,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email address'),
          onSubmitted: (_) => send(),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy || cooldown > 0 ? null : send,
          child: Text(
            busy
                ? 'Please wait...'
                : sent && cooldown > 0
                ? 'Resend in ${cooldown}s'
                : sent
                ? 'Send reset email again'
                : 'Send reset email',
          ),
        ),
        if (sent)
          TextButton(
            onPressed: busy
                ? null
                : () {
                    timer?.cancel();
                    setState(() {
                      sent = false;
                      cooldown = 0;
                      message = null;
                    });
                  },
            child: const Text('Use a different email'),
          ),
        if (message != null) Text(message!),
        if (sent)
          FilledButton(
            onPressed: () => context.go('/login'),
            child: const Text('Back to sign in'),
          ),
      ],
    ),
  );
}
