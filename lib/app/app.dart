import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';
import '../features/auth/application/auth_session.dart';
import '../features/auth/data/auth_repository.dart';

final authBootstrapEnabledProvider = Provider<bool>((ref) => true);

class OslavaApp extends ConsumerStatefulWidget {
  const OslavaApp({super.key});

  @override
  ConsumerState<OslavaApp> createState() => _OslavaAppState();
}

class _OslavaAppState extends ConsumerState<OslavaApp> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      if (!ref.read(authBootstrapEnabledProvider)) {
        return;
      }

      try {
        await ref
            .read(authSessionControllerProvider)
            .bootstrap(ref.read(authRepositoryProvider).loadCurrentSession);
      } on Object {
        ref.read(authSessionControllerProvider).clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Oslava Events',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
    );
  }
}
