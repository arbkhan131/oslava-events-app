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

  bool get canUseAdminAi {
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

  bool get canChangeWorkerCategory {
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
    this.accountStatus = 'ACTIVE',
    this.profileComplete = true,
    this.workerNumber,
  });

  final String userId;
  final AppRole role;
  final String displayName;
  final String accountStatus;
  final bool profileComplete;
  final int? workerNumber;
  bool get isRestricted => accountStatus != 'ACTIVE';
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
  int _generation = 0;
  bool loading = true;
  bool refreshing = false;
  bool _authFlowInProgress = false;
  String? error;

  AppSession? get session => _session;
  bool get authFlowInProgress => _authFlowInProgress;

  void setAuthFlowInProgress(bool value) {
    if (_authFlowInProgress == value) return;
    _authFlowInProgress = value;
    if (value) {
      _generation++;
      refreshing = false;
    }
    notifyListeners();
  }

  Future<void> bootstrap(Future<AppSession?> Function() loadSession) async {
    if (_hasBootstrapped) {
      return;
    }

    _hasBootstrapped = true;
    await refresh(loadSession);
  }

  Future<void> refresh(Future<AppSession?> Function() loadSession) async {
    if (_authFlowInProgress || refreshing) return;
    final generation = ++_generation;
    refreshing = true;
    try {
      final session = await loadSession();
      if (generation != _generation) return;
      _session = session;
      error = null;
    } catch (_) {
      if (generation != _generation) return;
      _session = null;
      error = 'Could not verify your account. Check your connection and retry.';
    } finally {
      if (generation == _generation) {
        refreshing = false;
        loading = false;
        notifyListeners();
      }
    }
  }

  void setSession(AppSession session) {
    _generation++;
    loading = false;
    refreshing = false;
    error = null;
    _session = session;
    notifyListeners();
  }

  void clear() {
    _generation++;
    refreshing = false;
    loading = false;
    error = null;
    _session = null;
    notifyListeners();
  }
}
