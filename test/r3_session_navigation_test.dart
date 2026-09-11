import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/app/app.dart';
import 'package:oslava_events/app/router/app_router.dart';
import 'package:oslava_events/features/auth/application/auth_session.dart';
import 'package:oslava_events/features/auth/data/auth_repository.dart';
import 'package:oslava_events/features/events/data/event_repository.dart';
import 'package:oslava_events/features/events/presentation/worker_event_list_screen.dart';
import 'package:oslava_events/features/workers/presentation/worker_directory_screen.dart';
import 'package:oslava_events/features/notifications/data/fcm_device_token_service.dart';
import 'package:oslava_events/features/notifications/data/notification_repository.dart';

AppSession session(
  String id, {
  AppRole role = AppRole.worker,
  String status = 'ACTIVE',
  bool complete = true,
}) => AppSession(
  userId: id,
  role: role,
  displayName: id,
  accountStatus: status,
  profileComplete: complete,
);

class FakeAuth implements AuthRepository {
  final changes = StreamController<void>.broadcast();
  AppSession? current;
  final List<String> order;
  FakeAuth(this.order);
  @override
  Stream<void> get sessionChanges => changes.stream;
  @override
  Future<AppSession?> loadCurrentSession() async => current;
  @override
  Future<void> signOut() async {
    order.add('signout');
    current = null;
  }

  @override
  String? get registrationPhone => null;
  @override
  Map<String, dynamic> get registrationDraft => {};
  @override
  Future<Map<String, dynamic>> loadPrivacyTerms() async => {
    'version': 'v2',
    'summary': 'Server terms',
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeNotifications implements NotificationRepository {
  final List<String> order;
  FakeNotifications(this.order);
  @override
  Future<bool> invalidateDeviceToken(String token) async {
    order.add('invalidate');
    return true;
  }

  @override
  Future<String> registerDeviceToken({
    required String token,
    required String platform,
    String? deviceId,
  }) async {
    order.add('register');
    return 'token-id';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class EmptyEvents implements EventRepository {
  @override
  Future<Never?> loadWorkerEventDetail(String id) async => null;
  @override
  Future<Never?> loadPendingBooking(String id) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('late bootstrap cannot restore a signed-out identity', () async {
    final controller = AuthSessionController();
    final loading = Completer<AppSession?>();
    final boot = controller.bootstrap(() => loading.future);
    controller.clear();
    loading.complete(session('old'));
    await boot;
    expect(controller.session, isNull);
    expect(controller.loading, false);
    controller.dispose();
  });
  test('failed session check is retryable and hides protected state', () async {
    final controller = AuthSessionController();
    controller.setSession(session('old'));
    await controller.refresh(() async => throw StateError('offline'));
    expect(controller.session, isNull);
    expect(controller.error, isNotNull);
    await controller.refresh(() async => session('new'));
    expect(controller.session!.userId, 'new');
    expect(controller.error, isNull);
    controller.dispose();
  });
  test('all role combinations reject cross-role deep links', () {
    for (final role in AppRole.values) {
      for (final target in AppRole.values) {
        expect(
          roleAwareRedirect(
            isAuthenticated: true,
            role: role,
            location: '${target.homePath}/events/id',
          ),
          role == target ? null : role.homePath,
        );
      }
    }
  });
  test('token registration cannot finish for an outgoing account', () async {
    var user = 'A';
    final permission = Completer<bool>();
    final order = <String>[];
    final service = FcmDeviceTokenService(
      FakeNotifications(order),
      currentUserId: () => user,
      permissionGranted: () => permission.future,
      tokenLoader: () async => 'token',
      tokenDeleter: () async {},
    );
    final registration = service.registerCurrentDevice();
    await service.invalidateCurrentDevice();
    user = 'B';
    permission.complete(true);
    await registration;
    expect(order, ['invalidate']);
  });
  test('denied notifications do not register a token', () async {
    final order = <String>[];
    final service = FcmDeviceTokenService(
      FakeNotifications(order),
      currentUserId: () => 'A',
      permissionGranted: () async => false,
    );
    expect(await service.registerCurrentDevice(), isNull);
    expect(order, isEmpty);
  });
  testWidgets('login remains scrollable above a phone keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authBootstrapEnabledProvider.overrideWithValue(false)],
        child: const OslavaApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Register as worker'));
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });
  testWidgets('nested feature routes support detail, list and home Back', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authBootstrapEnabledProvider.overrideWithValue(false),
          authSessionProvider.overrideWithValue(session('A')),
          eventRepositoryProvider.overrideWithValue(EmptyEvents()),
          workerEventsProvider.overrideWith((ref) async => []),
        ],
        child: const OslavaApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OslavaApp)),
    );
    final router = container.read(appRouterProvider);
    router.go('/worker/events/id');
    await tester.pumpAndSettle();
    expect(router.canPop(), true);
    router.pop();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/worker/events');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/worker');
  });
  testWidgets('identity changes clear cached feature data and search filters', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authBootstrapEnabledProvider.overrideWithValue(false),
          workerEventsProvider.overrideWith((ref) async {
            loads++;
            return [];
          }),
        ],
        child: const OslavaApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OslavaApp)),
    );
    container.read(authSessionControllerProvider).setSession(session('A'));
    await tester.pumpAndSettle();
    await container.read(workerEventsProvider.future);
    container.read(workerSearchTextProvider.notifier).state =
        'private A search';
    container.read(authSessionControllerProvider).setSession(session('B'));
    await tester.pumpAndSettle();
    await container.read(workerEventsProvider.future);
    expect(loads, 2);
    expect(container.read(workerSearchTextProvider), '');
  });
  testWidgets(
    'server restriction, restoration and signout follow auth events',
    (tester) async {
      final order = <String>[];
      final auth = FakeAuth(order)..current = session('A');
      final tokens = FcmDeviceTokenService(
        FakeNotifications(order),
        currentUserId: () => auth.current?.userId,
        permissionGranted: () async => false,
        tokenLoader: () async => 'token',
        tokenDeleter: () async {},
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            fcmDeviceTokenServiceProvider.overrideWithValue(tokens),
          ],
          child: const OslavaApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Worker'), findsOneWidget);
      auth.current = session('A', status: 'DETAINED');
      auth.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.textContaining('account is detained'), findsOneWidget);
      auth.current = session('A');
      auth.changes.add(null);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(order, ['invalidate', 'signout']);
      expect(find.text('Login'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.changes.close();
    },
  );
}
