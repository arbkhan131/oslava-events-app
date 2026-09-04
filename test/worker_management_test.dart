import 'package:flutter_test/flutter_test.dart';
import 'package:oslava_events/app/router/app_router.dart';
import 'package:oslava_events/features/auth/application/auth_session.dart';
import 'package:oslava_events/features/workers/domain/worker_profile.dart';

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
        'profile_completed_at': '2026-09-04T10:00:00Z',
      });

      expect(profile.workerNumber, 100001);
      expect(profile.role, AppRole.worker);
      expect(profile.accountStatus, AccountStatus.active);
      expect(profile.category, WorkerCategory.f);
      expect(profile.isComplete, isTrue);
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
