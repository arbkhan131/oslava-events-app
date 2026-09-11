import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/auth_session.dart';
import '../data/auth_repository.dart';
import '../domain/phone_number.dart';
import 'auth_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final phone = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    phone.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    final controller = ref.read(authSessionControllerProvider);
    setState(() {
      busy = true;
      error = null;
    });
    controller.setAuthFlowInProgress(true);
    try {
      if (password.text.isEmpty) {
        throw const FormatException('Enter your password.');
      }
      final session = await ref
          .read(authRepositoryProvider)
          .signInWithPhonePassword(
            phone: PhoneNumber.parse(phone.text),
            password: password.text,
          );
      controller.setAuthFlowInProgress(false);
      controller.setSession(session);
      if (mounted) {
        context.go(
          session.isRestricted
              ? '/session'
              : session.profileComplete
              ? session.role.homePath
              : '/register',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyAuthError(e));
    } finally {
      controller.setAuthFlowInProgress(false);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Oslava Events')),
    body: AuthFormBody(
      children: [
        Text('Login', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        TextField(
          controller: phone,
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
        PasswordField(controller: password, onSubmitted: (_) => submit()),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(busy ? 'Signing in…' : 'Sign in'),
        ),
        TextButton(
          onPressed: busy ? null : () => context.push('/register'),
          child: const Text('Register as worker'),
        ),
      ],
    ),
  );
}
