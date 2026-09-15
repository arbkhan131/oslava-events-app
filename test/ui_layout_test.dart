import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/app/theme/app_theme.dart';
import 'package:oslava_events/features/auth/presentation/login_screen.dart';
import 'package:oslava_events/features/auth/presentation/worker_registration_screen.dart';
import 'package:oslava_events/features/auth/data/auth_repository.dart';
import 'package:oslava_events/features/events/domain/event_summary.dart';
import 'package:oslava_events/features/events/domain/worker_event.dart';
import 'package:oslava_events/features/events/presentation/worker_event_list_screen.dart';
import 'package:oslava_events/features/auth/presentation/session_status_screen.dart';
import 'package:oslava_events/features/auth/application/auth_session.dart';
import 'package:oslava_events/features/workers/presentation/worker_directory_screen.dart';
import 'package:oslava_events/features/notifications/presentation/alerts_screen.dart';
import 'package:oslava_events/features/events/presentation/worker_my_work_screen.dart';
import 'package:oslava_events/features/booking/domain/worker_assignment.dart';

WorkerAssignment previewAssignment() => WorkerAssignment(
  assignmentId: 'preview-assignment',
  eventId: 'preview-event',
  title: 'Evening wedding reception',
  venueName: 'Grand Convention Centre, Kozhikode',
  reportingAt: DateTime.utc(2026, 9, 20, 10),
  expectedEndsAt: DateTime.utc(2026, 9, 20, 18),
  status: AssignmentStatus.confirmed,
  cancellationDeadlineAt: DateTime.utc(2026, 9, 19, 10),
  canCancel: true,
);

class _RegistrationAuth implements AuthRepository {
  @override
  String? get registrationPhone => null;
  @override
  Map<String, dynamic> get registrationDraft => {};
  @override
  Future<Map<String, dynamic>> loadPrivacyTerms() async => {
    'version': 'v2',
    'summary': 'Privacy terms',
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget host(Widget child, {double scale = 1}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildAppTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);

void main() {
  testWidgets('work cards wrap and cancellation requires an explicit reason', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workerAssignmentsProvider.overrideWith(
            (ref) async => [previewAssignment()],
          ),
          workerWaitlistProvider.overrideWith((ref) async => []),
        ],
        child: host(const WorkerMyWorkScreen(), scale: 1.6),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel assignment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a reason to continue.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('pending approval explains review and allows status checking', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AuthSessionController()
      ..setSession(
        const AppSession(
          userId: 'pending',
          role: AppRole.worker,
          displayName: 'New Worker',
          accountStatus: 'PENDING_APPROVAL',
        ),
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionControllerProvider.overrideWith((ref) => controller),
        ],
        child: host(const SessionStatusScreen(), scale: 1.5),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Registration received'), findsOneWidget);
    await tester.ensureVisible(find.text('Check approval status'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('staff creation stays usable with keyboard and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workerDirectoryProvider.overrideWith((ref) async => []),
          staffDirectoryProvider.overrideWith((ref) async => []),
        ],
        child: host(
          const WorkerDirectoryScreen(role: AppRole.superAdmin),
          scale: 1.5,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Add staff account'));
    await tester.tap(find.byTooltip('Add staff account'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reason'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Create'), findsOneWidget);
  });

  testWidgets('alerts offer recovery without exposing technical errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          alertsProvider.overrideWith(
            (ref) async => throw StateError('internal failure'),
          ),
        ],
        child: host(const AlertsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('internal failure'), findsNothing);
  });

  if (const bool.fromEnvironment('UI_PREVIEW')) {
    testWidgets('render pending approval preview', (tester) async {
      const fontDirectory = String.fromEnvironment('UI_FONT_DIRECTORY');
      await tester.runAsync(() async {
        final textFont = FontLoader('Roboto');
        textFont.addFont(
          File('$fontDirectory/roboto-regular.ttf')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
        await textFont.load();
        final icons = FontLoader('MaterialIcons');
        icons.addFont(
          File('$fontDirectory/materialicons-regular.otf')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
        await icons.load();
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = AuthSessionController()
        ..setSession(
          const AppSession(
            userId: 'preview',
            role: AppRole.worker,
            displayName: 'Worker',
            accountStatus: 'PENDING_APPROVAL',
          ),
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionControllerProvider.overrideWith((ref) => controller),
          ],
          child: host(const SessionStatusScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../build/ui-review/pending.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workerAssignmentsProvider.overrideWith(
              (ref) async => [previewAssignment()],
            ),
            workerWaitlistProvider.overrideWith((ref) async => []),
          ],
          child: host(const WorkerMyWorkScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../build/ui-review/my-work.png'),
      );
    });
  }
  testWidgets('login remains scrollable with keyboard and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(child: host(const LoginScreen(), scale: 1.6)),
    );
    await tester.enterText(find.byType(TextField).first, '9876543210');
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.ensureVisible(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Register as worker'), findsOneWidget);
  });

  testWidgets('registration sections preserve old-only category selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_RegistrationAuth()),
        ],
        child: host(const WorkerRegistrationScreen(), scale: 1.3),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Old worker category'), findsNothing);
    await tester.tap(find.text('Old worker'));
    await tester.pumpAndSettle();
    expect(find.text('Old worker category'), findsOneWidget);
    await tester.ensureVisible(find.text('Submit registration'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('long event details wrap at narrow width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final event = WorkerEvent(
      id: 'preview',
      title: 'Evening wedding reception and celebration',
      eventType: 'Wedding',
      venueName: 'Grand convention centre, Kozhikode, Kerala',
      eventDate: DateTime(2026, 9, 20),
      reportingAt: DateTime.utc(2026, 9, 20, 9),
      workStartsAt: DateTime.utc(2026, 9, 20, 10),
      expectedEndsAt: DateTime.utc(2026, 9, 20, 17),
      requiredWorkerCount: 20,
      activeConfirmedCount: 12,
      vacancyCount: 8,
      dailyWage: 1200,
      currencyCode: 'INR',
      eventStatus: EventStatus.published,
      recruitmentStatus: RecruitmentStatus.open,
      tierStrategy: TierStrategy.standard,
      openCategories: ['A', 'B', 'C', 'F'],
      actionState: WorkerEventActionState.available,
      actionLabel: 'Available',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workerEventsProvider.overrideWith((ref) async => [event]),
        ],
        child: host(const WorkerEventListScreen(), scale: 1.6),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('View event →'), 200);
    expect(tester.takeException(), isNull);
    expect(find.text('8 vacant'), findsOneWidget);
  });
}
