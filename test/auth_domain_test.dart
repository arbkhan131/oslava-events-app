import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:oslava_events/features/auth/application/auth_session.dart';
import 'package:oslava_events/features/auth/data/profile_photo_preparer.dart';
import 'package:oslava_events/features/auth/domain/phone_number.dart';
import 'package:oslava_events/features/auth/domain/worker_registration_input.dart';

void main() {
  group('PhoneNumber', () {
    test('normalizes E.164 phone text', () {
      expect(PhoneNumber.parse('+91 98765-43210').value, '+919876543210');
      expect(PhoneNumber.parse('9876543210').value, '+919876543210');
      expect(
        PhoneNumber.parse('919876543210').authEmail,
        '919876543210@phone.oslava.local',
      );
    });

    test('rejects non-phone identifiers such as Worker IDs', () {
      expect(() => PhoneNumber.parse('100001'), throwsFormatException);
    });
  });

  group('AppRoleParsing', () {
    test('maps database labels to app roles', () {
      expect(AppRoleParsing.fromDatabase('WORKER'), AppRole.worker);
      expect(AppRole.admin.databaseValue, 'ADMIN');
    });
  });

  group('WorkerRegistrationInput', () {
    test('serializes RPC parameters using trimmed required fields', () {
      final input = WorkerRegistrationInput(
        registrationType: WorkerRegistrationType.oldWorker,
        fullName: ' Worker One ',
        phone: PhoneNumber.parse('+919876543210'),
        password: 'secret-password',
        profilePhotoPath: 'user/profile.jpg',
        idCardFilePath: 'user/id.pdf',
        dateOfBirth: DateTime(2000, 1, 2),
        place: ' Pune ',
        heightCm: 172.5,
        educationStatus: ' College ',
        experienceLevel: WorkerExperienceLevel.someExperience,
        requestedCategory: RegistrationWorkerCategory.b,
        privacyTermsVersion: ' v1.0 ',
      );

      expect(input.toRpcParams(), containsPair('full_name', 'Worker One'));
      expect(input.toRpcParams(), containsPair('native_place', 'Pune'));
      expect(
        input.toRpcParams(),
        containsPair('registration_type', 'OLD_WORKER'),
      );
      expect(
        input.toRpcParams(),
        containsPair('experience_level', 'SOME_EXPERIENCE'),
      );
      expect(input.toRpcParams(), containsPair('p_requested_category', 'B'));
      expect(input.toRpcParams(), containsPair('date_of_birth', '2000-01-02'));
      expect(input.toRpcParams(), containsPair('height_cm', 172.5));
      expect(
        input.toRpcParams(),
        containsPair('privacy_terms_version', 'v1.0'),
      );
    });

    test('requires complete fields before submission', () {
      final input = WorkerRegistrationInput(
        registrationType: WorkerRegistrationType.newWorker,
        fullName: '',
        phone: PhoneNumber.parse('+919876543210'),
        password: 'secret-password',
        profilePhotoPath: 'user/profile.jpg',
        idCardFilePath: 'user/id.pdf',
        dateOfBirth: DateTime(2000),
        place: 'Pune',
        heightCm: 172.5,
        educationStatus: 'College',
        experienceLevel: WorkerExperienceLevel.noExperience,
        privacyTermsVersion: 'v1.0',
      );

      expect(input.validate, throwsFormatException);
    });
  });

  group('ProfilePhotoPreparer', () {
    test('rejects unsupported MIME types', () {
      expect(
        () => const ProfilePhotoPreparer().prepare(
          userId: 'user-id',
          sourceBytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'image/gif',
        ),
        throwsFormatException,
      );
    });

    test(
      'resizes and compresses supported images for private storage path',
      () {
        final image = img.Image(width: 1600, height: 900);
        img.fill(image, color: img.ColorRgb8(40, 90, 170));
        final bytes = Uint8List.fromList(img.encodePng(image));

        final prepared = const ProfilePhotoPreparer().prepare(
          userId: '00000000-0000-0000-0000-000000000101',
          sourceBytes: bytes,
          mimeType: 'image/png',
        );

        expect(prepared.mimeType, 'image/jpeg');
        expect(
          prepared.storagePath,
          '00000000-0000-0000-0000-000000000101/profile.jpg',
        );
        expect(prepared.bytes.lengthInBytes, lessThanOrEqualTo(1024 * 1024));
        final decoded = img.decodeImage(prepared.bytes);
        expect(decoded?.width, decoded?.height);
        expect(decoded?.width, lessThanOrEqualTo(1024));
      },
    );
  });
}
