import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/logout.dart';

class SignOutButton extends ConsumerStatefulWidget {
  const SignOutButton({super.key});
  @override
  ConsumerState<SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends ConsumerState<SignOutButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.logout_rounded, size: 18),
    label: Text(_busy ? 'Signing out…' : 'Sign out'),
    onPressed: _busy
        ? null
        : () async {
            setState(() => _busy = true);
            try {
              await logout(ref);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not sign out. Please retry.'),
                  ),
                );
              }
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
  );
}
