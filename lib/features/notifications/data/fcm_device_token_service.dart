import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_repository.dart';
import '../../../app/bootstrap.dart';

final fcmDeviceTokenServiceProvider = Provider<FcmDeviceTokenService>(
  (ref) => FcmDeviceTokenService(
    ref.watch(notificationRepositoryProvider),
    currentUserId: () => ref.read(supabaseClientProvider).auth.currentUser?.id,
  ),
);

class FcmDeviceTokenService {
  FcmDeviceTokenService(
    this._repository, {
    required this.currentUserId,
    this.permissionGranted,
    this.tokenLoader,
    this.tokenDeleter,
  });

  final NotificationRepository _repository;
  final String? Function() currentUserId;
  int _generation = 0;
  Future<void>? _pendingWrite;
  bool _acceptRefreshes = false;
  final Future<bool> Function()? permissionGranted;
  final Future<String?> Function()? tokenLoader;
  final Future<void> Function()? tokenDeleter;
  Future<String?> _token() =>
      tokenLoader?.call() ?? FirebaseMessaging.instance.getToken();

  Future<void> _register(String token, String userId, int generation) {
    _pendingWrite = (_pendingWrite ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) async {
          if (generation != _generation || currentUserId() != userId) return;
          await _repository.registerDeviceToken(
            token: token,
            platform: _platform,
          );
        });
    return _pendingWrite!;
  }

  Future<String?> registerCurrentDevice() async {
    final userId = currentUserId();
    final generation = _generation;
    final allowed = permissionGranted == null
        ? (await FirebaseMessaging.instance.requestPermission())
                  .authorizationStatus !=
              AuthorizationStatus.denied
        : await permissionGranted!();
    if (!allowed) return null;
    final token = await _token();
    if (token == null || token.trim().isEmpty) {
      return null;
    }

    if (userId == null ||
        currentUserId() != userId ||
        generation != _generation) {
      return null;
    }
    await _register(token, userId, generation);
    if (generation != _generation || currentUserId() != userId) return null;
    _acceptRefreshes = true;
    return token;
  }

  Future<void> registerRefreshedToken(String token) async {
    final userId = currentUserId();
    if (userId == null || !_acceptRefreshes) return;
    await _register(token, userId, _generation);
  }

  Future<bool> invalidateCurrentDevice() async {
    _generation++;
    _acceptRefreshes = false;
    try {
      await _pendingWrite;
    } catch (_) {}
    final token = await _token();
    if (token == null || token.trim().isEmpty) {
      return false;
    }
    try {
      return await _repository.invalidateDeviceToken(token);
    } finally {
      await (tokenDeleter?.call() ?? FirebaseMessaging.instance.deleteToken());
    }
  }

  Stream<String> get tokenRefreshes =>
      FirebaseMessaging.instance.onTokenRefresh;

  String get _platform {
    if (kIsWeb) {
      return 'web';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return 'other';
    }
  }
}
