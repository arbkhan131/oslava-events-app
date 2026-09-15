import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_session.dart';
import '../application/logout.dart';
import '../data/auth_repository.dart';
import 'auth_widgets.dart';
import '../../../core/widgets/app_feedback.dart';

class SessionStatusScreen extends ConsumerWidget {
  const SessionStatusScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(authSessionControllerProvider);
    final session = controller.session;
    final message = controller.error ?? _statusMessage(session);
    final pending = session?.accountStatus == 'PENDING_APPROVAL';
    return Scaffold(
      appBar: AppBar(title: const Text('Your account')),
      body: AuthFormBody(
        children: [
          if (controller.loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            AppEmptyState(
              icon: pending
                  ? Icons.hourglass_top_rounded
                  : Icons.manage_accounts_outlined,
              title: pending ? 'You’re on the list!' : 'Account access',
              message: pending
                  ? 'Your profile has been submitted for review.'
                  : message,
            ),
            if (pending) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pending approval',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.check_circle_outline,
                          color: Color(0xFF167568),
                        ),
                        title: Text('Registration received'),
                        subtitle: Text('Your details are ready for review.'),
                      ),
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.people_outline),
                        title: Text('Team review'),
                        subtitle: Text(
                          'A captain or supervisor will review your profile and documents.',
                        ),
                      ),
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.event_available_outlined),
                        title: Text('Start receiving work'),
                        subtitle: Text(
                          'Events and notifications become available after approval.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (controller.error != null)
                AppNotice(message: controller.error!, isError: true),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: controller.refreshing
                  ? null
                  : () => controller.refresh(
                      ref.read(authRepositoryProvider).loadCurrentSession,
                    ),
              child: Text(
                controller.refreshing
                    ? 'Checking status…'
                    : pending
                    ? 'Check approval status'
                    : 'Retry account check',
              ),
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
