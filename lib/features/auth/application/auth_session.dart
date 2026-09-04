import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppRole {
  superAdmin,
  admin,
  captain,
  supervisor,
  worker;

  String get label {
    switch (this) {
      case AppRole.superAdmin:
        return 'Super Admin';
      case AppRole.admin:
        return 'Admin';
      case AppRole.captain:
        return 'Captain';
      case AppRole.supervisor:
        return 'Supervisor';
      case AppRole.worker:
        return 'Worker';
    }
  }

  String get homePath {
    switch (this) {
      case AppRole.superAdmin:
        return '/super-admin';
      case AppRole.admin:
        return '/admin';
      case AppRole.captain:
        return '/captain';
      case AppRole.supervisor:
        return '/supervisor';
      case AppRole.worker:
        return '/worker';
    }
  }
}

class AppSession {
  const AppSession({
    required this.userId,
    required this.role,
    required this.displayName,
  });

  final String userId;
  final AppRole role;
  final String displayName;
}

final authSessionProvider = Provider<AppSession?>((ref) => null);
