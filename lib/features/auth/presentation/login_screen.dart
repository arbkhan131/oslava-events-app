import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/auth_session.dart';
import '../data/auth_repository.dart';
import '../domain/phone_number.dart';
import 'auth_widgets.dart';
import '../../../core/widgets/app_feedback.dart';

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
    FocusManager.instance.primaryFocus?.unfocus();
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
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF173F7A), Color(0xFF167568)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.event_available_rounded,
                color: Colors.white,
                size: 36,
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome back',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your team. Your next event.',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text('Login', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text('Use your WhatsApp number and password to continue.'),
        const SizedBox(height: 20),
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
            child: AppNotice(message: error!, isError: true),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(busy ? 'Signing in…' : 'Sign in'),
        ),
        const SizedBox(height: 24),
        const Text('New to the team?', textAlign: TextAlign.center),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: busy ? null : () => context.push('/register'),
          child: const Text('Register as worker'),
        ),
      ],
    ),
  );
}
