import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../../notifications/data/fcm_device_token_service.dart';
import 'auth_session.dart';

Future<void> logout(WidgetRef ref) async {
  final controller = ref.read(authSessionControllerProvider);
  controller.setAuthFlowInProgress(true);
  try {
    // The token RPC needs the outgoing session. Do this before Auth discards it.
    try {
      await ref.read(fcmDeviceTokenServiceProvider).invalidateCurrentDevice();
    } catch (_) {}
    await ref.read(authRepositoryProvider).signOut();
    controller.clear();
  } finally {
    controller.setAuthFlowInProgress(false);
  }
}
