import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/app/router/app_router.dart';
import 'package:oslava_events/features/auth/application/auth_session.dart';
import 'package:oslava_events/features/workers/data/worker_repository.dart';
import 'package:oslava_events/features/workers/domain/worker_profile.dart';
import 'package:oslava_events/features/workers/presentation/worker_directory_screen.dart';

class FakeWorkerRepository implements WorkerRepository {
  WorkerDirectoryQuery? lastQuery;
  final List<StaffProvisionRequest> provisions = [];
  final List<String> phoneChanges = [];

  @override
  Future<List<WorkerProfile>> searchWorkers(WorkerDirectoryQuery query) async {
    lastQuery = query;
    return [
      WorkerProfile.fromJson({
        'user_id': 'worker-id',
        'worker_number': 100001,
        'full_name': 'Worker One',
        'initials': 'WO',
        'phone_e164': '+919876543210',
        'profile_photo_path': 'worker-id/profile.jpg',
        'role': 'WORKER',
        'account_status': 'ACTIVE',
        'category': 'F',
        'last_worker_category': 'F',
        'profile_completed_at': '2026-09-04T10:00:00Z',
      }),
    ];
  }

  @override
  Future<List<StaffProfile>> searchStaff({
    String? searchText,
    AppRole? role,
    AccountStatus? accountStatus,
    int limit = 50,
    int offset = 0,
  }) async {
    return [
      StaffProfile.fromJson({
        'user_id': 'captain-id',
        'full_name': 'Captain One',
        'initials': 'CO',
        'phone_e164': '+919876543211',
        'role': 'CAPTAIN',
        'account_status': 'ACTIVE',
      }),
    ];
  }

  @override
  Future<String?> signedProfilePhotoUrl(String? storagePath) async => null;

  @override
  Future<String> provisionStaff(StaffProvisionRequest request) async {
    provisions.add(request);
    return 'new-staff-id';
  }

  @override
  Future<void> changeUserPhone({
    required String userId,
    required String phoneE164,
    required String reason,
  }) async {
    phoneChanges.add('$userId:$phoneE164:$reason');
  }

  @override
  Future<WorkerProfile> loadOwnWorkerProfile() async =>
      throw UnimplementedError();

  @override
  Future<List<ErasureRequestStatus>> loadMyErasureRequests() async => [];

  @override
  Future<String> requestMyAccountErasure(String reason) async => 'request-id';

  @override
  Future<void> updateOwnProfile(WorkerProfileUpdate update) async {}

  @override
  Future<void> replaceOwnProfilePhoto({
    required String storagePath,
    required Uint8List bytes,
    required String mimeType,
    String? oldStoragePath,
    required WorkerProfileUpdate currentProfile,
  }) async {}

  @override
  Future<WorkerProfile> loadWorkerDetail(String userId) async =>
      throw UnimplementedError();

  @override
  Future<List<WorkerHistoryEntry>> loadWorkerHistory(String userId) async => [];

  @override
  Future<void> detainWorker({
    required String userId,
    required String reason,
    String? notes,
  }) async {}

  @override
  Future<void> releaseWorker({
    required String userId,
    required String reason,
    String? notes,
  }) async {}

  @override
  Future<WorkerCategoryChangeResult> changeWorkerCategory({
    required String userId,
    required WorkerCategory newCategory,
    required String reason,
    String? notes,
  }) async {
    return WorkerCategoryChangeResult(
      workerId: userId,
      oldCategory: WorkerCategory.f,
      newCategory: newCategory,
    );
  }
}

void main() {
  group('Phase 4 role capabilities', () {
    test('field and admin roles can browse workers', () {
      expect(AppRole.superAdmin.canBrowseWorkers, isTrue);
      expect(AppRole.admin.canBrowseWorkers, isTrue);
      expect(AppRole.captain.canBrowseWorkers, isTrue);
      expect(AppRole.supervisor.canBrowseWorkers, isTrue);
      expect(AppRole.worker.canBrowseWorkers, isFalse);
    });

    test('only Admin and Super Admin can detain workers', () {
      expect(AppRole.superAdmin.canDetainWorkers, isTrue);
      expect(AppRole.admin.canDetainWorkers, isTrue);
      expect(AppRole.captain.canDetainWorkers, isFalse);
      expect(AppRole.supervisor.canDetainWorkers, isFalse);
      expect(AppRole.worker.canDetainWorkers, isFalse);
    });

    test('field and admin roles can change Worker categories', () {
      expect(AppRole.superAdmin.canChangeWorkerCategory, isTrue);
      expect(AppRole.admin.canChangeWorkerCategory, isTrue);
      expect(AppRole.captain.canChangeWorkerCategory, isTrue);
      expect(AppRole.supervisor.canChangeWorkerCategory, isTrue);
      expect(AppRole.worker.canChangeWorkerCategory, isFalse);
    });
  });

  group('ErasureRequestStatus parsing', () {
    test('parses deletion request status rows', () {
      final status = ErasureRequestStatus.fromJson({
        'request_id': 'request-id',
        'status': 'OPEN',
        'verification_status': 'PENDING_VERIFICATION',
        'due_at': '2026-10-10T10:00:00Z',
        'completed_at': null,
        'completion_notes': null,
        'photo_cleanup_status': 'NOT_REQUIRED',
        'created_at': '2026-09-10T10:00:00Z',
      });

      expect(status.id, 'request-id');
      expect(status.isOpen, true);
      expect(status.label, 'Pending verification');
    });
  });

  group('WorkerProfile parsing', () {
    test('maps directory rows into profile summaries', () {
      final profile = WorkerProfile.fromJson({
        'user_id': 'worker-id',
        'worker_number': 100001,
        'full_name': 'Worker One',
        'initials': 'WO',
        'phone_e164': '+919876543210',
        'profile_photo_path': 'worker-id/profile.jpg',
        'role': 'WORKER',
        'account_status': 'ACTIVE',
        'category': 'F',
        'last_worker_category': 'F',
        'reliability_score': 87.5,
        'reliability_state': 'RATED',
        'reliability_sample_count': 4,
        'reliability_present_count': 2,
        'reliability_late_count': 1,
        'reliability_absent_count': 1,
        'reliability_worker_cancellation_count': 1,
        'reliability_completed_event_count': 3,
        'reliability_performance_event_count': 2,
        'reliability_performance_average': 4.25,
        'reliability_config_version': 1,
        'reliability_computed_at': '2026-10-12T10:00:00Z',
        'profile_completed_at': '2026-09-04T10:00:00Z',
      });

      expect(profile.workerNumber, 100001);
      expect(profile.role, AppRole.worker);
      expect(profile.accountStatus, AccountStatus.active);
      expect(profile.category, WorkerCategory.f);
      expect(profile.isComplete, isTrue);
      expect(profile.reliabilityState, ReliabilityState.rated);
      expect(profile.reliabilitySampleCount, 4);
      expect(profile.reliabilityPresentCount, 2);
      expect(profile.reliabilityLateCount, 1);
      expect(profile.reliabilityAbsentCount, 1);
      expect(profile.reliabilityWorkerCancellationCount, 1);
      expect(profile.reliabilityCompletedEventCount, 3);
      expect(profile.reliabilityPerformanceEventCount, 2);
      expect(profile.reliabilityPerformanceAverage, 4.25);
      expect(profile.reliabilityConfigVersion, 1);
    });

    test('maps provisional reliability state labels', () {
      expect(
        ReliabilityState.provisional.label(2),
        'Provisional - 2 of 3 commitments',
      );
      expect(ReliabilityState.rated.label(3), 'Rated');
    });

    test('offers only one-step category options', () {
      expect(WorkerCategory.a.oneStepOptions, [WorkerCategory.b]);
      expect(WorkerCategory.b.oneStepOptions, [
        WorkerCategory.a,
        WorkerCategory.c,
      ]);
      expect(WorkerCategory.c.oneStepOptions, [
        WorkerCategory.b,
        WorkerCategory.f,
      ]);
      expect(WorkerCategory.f.oneStepOptions, [WorkerCategory.c]);
    });

    test('parses category change results', () {
      final result = WorkerCategoryChangeResult.fromJson({
        'worker_id': 'worker-id',
        'old_category': 'B',
        'new_category': 'A',
      });

      expect(result.workerId, 'worker-id');
      expect(result.oldCategory, WorkerCategory.b);
      expect(result.newCategory, WorkerCategory.a);
    });

    test('models staff provisioning request body', () {
      final request = StaffProvisionRequest(
        fullName: 'Captain One',
        initials: 'CO',
        email: 'captain@example.test',
        phoneE164: '+919876543211',
        password: 'temporary-secret',
        role: AppRole.captain,
        reason: 'Field lead setup',
      );

      expect(request.toFunctionBody(), {
        'action': 'provision_staff',
        'email': 'captain@example.test',
        'phone': '+919876543211',
        'password': 'temporary-secret',
        'full_name': 'Captain One',
        'initials': 'CO',
        'role': 'CAPTAIN',
        'reason': 'Field lead setup',
      });
    });
  });

  group('R4 worker directory UI', () {
    testWidgets('loads paginated workers and staff accounts', (tester) async {
      final repository = FakeWorkerRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [workerRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: WorkerDirectoryScreen(role: AppRole.admin),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.lastQuery?.limit, 50);
      expect(repository.lastQuery?.offset, 0);
      expect(find.text('Worker One'), findsOneWidget);
      expect(find.text('Team accounts'), findsOneWidget);

      await tester.tap(find.text('Team accounts'));
      await tester.pumpAndSettle();
      expect(find.text('Captain One'), findsOneWidget);
    });
  });

  group('Phase 4 route guard', () {
    test('Worker cannot open admin worker directory routes', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.worker,
          location: '/admin/workers',
        ),
        '/worker',
      );
    });

    test('Captain cannot open admin detention routes', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.captain,
          location: '/admin/workers/worker-id',
        ),
        '/captain',
      );
    });

    test('Admin can open admin worker routes', () {
      expect(
        roleAwareRedirect(
          isAuthenticated: true,
          role: AppRole.admin,
          location: '/admin/workers',
        ),
        isNull,
      );
    });
  });
}
