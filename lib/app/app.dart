import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';
import '../features/auth/application/auth_session.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/notifications/data/fcm_device_token_service.dart';

final authBootstrapEnabledProvider = Provider<bool>((ref) => true);

class OslavaApp extends ConsumerStatefulWidget {
  const OslavaApp({super.key});

  @override
  ConsumerState<OslavaApp> createState() => _OslavaAppState();
}

class _OslavaAppState extends ConsumerState<OslavaApp>
    with WidgetsBindingObserver {
  AppSession? _registeredNotificationSession;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<void>? _authSubscription;
  Timer? _refreshTimer;
  int _tokenGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.microtask(() async {
      if (!ref.read(authBootstrapEnabledProvider)) {
        return;
      }
      _authSubscription = ref
          .read(authRepositoryProvider)
          .sessionChanges
          .listen(
            (_) {
              if (mounted) unawaited(_refreshSession());
            },
            onError: (Object _, StackTrace _) {
              if (mounted) unawaited(_refreshSession());
            },
          );
      _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed) {
          unawaited(_refreshSession());
        }
      });
      try {
        await ref
            .read(authSessionControllerProvider)
            .bootstrap(ref.read(authRepositoryProvider).loadCurrentSession);
      } on Object {
        // The controller exposes a retryable error instead of treating network failure as logout.
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _refreshTimer?.cancel();
    _tokenRefreshSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshSession() async {
    if (!mounted || !ref.read(authBootstrapEnabledProvider)) return;
    await ref
        .read(authSessionControllerProvider)
        .refresh(ref.read(authRepositoryProvider).loadCurrentSession);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshSession());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppSession?>(
      derivedAuthSessionProvider,
      _syncNotificationTokenForSession,
    );

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Oslava Events',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
    );
  }

  void _syncNotificationTokenForSession(
    AppSession? previous,
    AppSession? next,
  ) {
    if (previous?.userId != next?.userId ||
        previous?.role != next?.role ||
        previous?.accountStatus != next?.accountStatus) {
      invalidateUserData(ref);
      _tokenGeneration++;
    }
    if (next == null || next.isRestricted || !next.profileComplete) {
      _registeredNotificationSession = null;
      unawaited(_tokenRefreshSubscription?.cancel());
      _tokenRefreshSubscription = null;
      return;
    }

    if (_registeredNotificationSession?.userId == next.userId) {
      return;
    }

    unawaited(_registerNotificationToken(next));
  }

  Future<void> _registerNotificationToken(AppSession session) async {
    final generation = _tokenGeneration;
    try {
      final service = ref.read(fcmDeviceTokenServiceProvider);
      await service.registerCurrentDevice();
      if (!mounted || generation != _tokenGeneration) return;
      _registeredNotificationSession = session;
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = service.tokenRefreshes.listen((token) {
        if (_registeredNotificationSession == null) {
          return;
        }
        unawaited(
          service.registerRefreshedToken(token).catchError((Object _) {}),
        );
      });
    } on Object {
      // Notification token registration must not block authenticated app use.
    }
  }
}
