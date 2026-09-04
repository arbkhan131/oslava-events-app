import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

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

  bool get canBrowseWorkers {
    switch (this) {
      case AppRole.superAdmin:
      case AppRole.admin:
      case AppRole.captain:
      case AppRole.supervisor:
        return true;
      case AppRole.worker:
        return false;
    }
  }

  bool get canDetainWorkers {
    switch (this) {
      case AppRole.superAdmin:
      case AppRole.admin:
        return true;
      case AppRole.captain:
      case AppRole.supervisor:
      case AppRole.worker:
        return false;
    }
  }
}

extension AppRoleParsing on AppRole {
  static AppRole fromDatabase(String value) {
    switch (value) {
      case 'SUPER_ADMIN':
        return AppRole.superAdmin;
      case 'ADMIN':
        return AppRole.admin;
      case 'CAPTAIN':
        return AppRole.captain;
      case 'SUPERVISOR':
        return AppRole.supervisor;
      case 'WORKER':
        return AppRole.worker;
      default:
        throw FormatException('Unknown app role "$value".');
    }
  }

  String get databaseValue {
    switch (this) {
      case AppRole.superAdmin:
        return 'SUPER_ADMIN';
      case AppRole.admin:
        return 'ADMIN';
      case AppRole.captain:
        return 'CAPTAIN';
      case AppRole.supervisor:
        return 'SUPERVISOR';
      case AppRole.worker:
        return 'WORKER';
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

final authSessionControllerProvider = ChangeNotifierProvider(
  (ref) => AuthSessionController(),
);

final derivedAuthSessionProvider = Provider<AppSession?>(
  (ref) => ref.watch(authSessionControllerProvider).session,
);

class AuthSessionController extends ChangeNotifier {
  AppSession? _session;
  bool _hasBootstrapped = false;

  AppSession? get session => _session;

  Future<void> bootstrap(Future<AppSession?> Function() loadSession) async {
    if (_hasBootstrapped) {
      return;
    }

    _hasBootstrapped = true;
    _session = await loadSession();
    notifyListeners();
  }

  void setSession(AppSession session) {
    _session = session;
    notifyListeners();
  }

  void clear() {
    _session = null;
    notifyListeners();
  }
}
