import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_session.dart';
import '../application/logout.dart';
import '../data/auth_repository.dart';
import 'auth_widgets.dart';

class SessionStatusScreen extends ConsumerWidget {
  const SessionStatusScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(authSessionControllerProvider);
    final session = controller.session;
    final message = controller.error ?? _statusMessage(session);
    return Scaffold(
      appBar: AppBar(title: const Text('Your account')),
      body: AuthFormBody(
        children: [
          if (controller.loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            if (session?.accountStatus == 'PENDING_APPROVAL') ...[
              const SizedBox(height: 8),
              const Text(
                'A captain or supervisor must approve your registration before events and notifications are enabled for you.',
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: controller.refreshing
                  ? null
                  : () => controller.refresh(
                      ref.read(authRepositoryProvider).loadCurrentSession,
                    ),
              child: const Text('Retry account check'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await logout(ref);
                } catch (_) {}
              },
              child: const Text('Sign out'),
            ),
          ],
        ],
      ),
    );
  }

  String _statusMessage(AppSession? session) {
    switch (session?.accountStatus) {
      case 'PENDING_APPROVAL':
        return 'Your registration is pending approval.';
      case 'REJECTED':
        return 'Your registration was rejected. Contact a captain or supervisor for help.';
      case 'SUSPENDED':
        return 'Your account is suspended.';
      case 'DETAINED':
        return 'Your account is detained.';
      case 'BLACKLISTED':
        return 'Your account is blacklisted.';
      case 'INACTIVE':
        return 'Your account is inactive.';
      default:
        return 'Your account is currently restricted. Contact your administrator for help.';
    }
  }
}
