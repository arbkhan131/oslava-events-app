import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/prepared_profile_photo.dart';

class ProfilePhotoPreparer {
  const ProfilePhotoPreparer();

  static const allowedMimeTypes = {'image/jpeg', 'image/png', 'image/webp'};
  static const maxSourceBytes = 5 * 1024 * 1024;
  static const targetBytes = 1024 * 1024;

  PreparedProfilePhoto prepare({
    required String userId,
    required Uint8List sourceBytes,
    required String mimeType,
  }) {
    if (!allowedMimeTypes.contains(mimeType)) {
      throw const FormatException('Unsupported profile photo type.');
    }

    if (sourceBytes.lengthInBytes > maxSourceBytes) {
      throw const FormatException('Profile photo must be 5 MB or smaller.');
    }

    img.Image? decoded;
    try {
      decoded = img.decodeImage(sourceBytes);
    } catch (_) {
      throw const FormatException('Profile photo could not be decoded.');
    }
    if (decoded == null) {
      throw const FormatException('Profile photo could not be decoded.');
    }

    final side = decoded.width < decoded.height
        ? decoded.width
        : decoded.height;
    final cropped = img.copyCrop(
      decoded,
      x: ((decoded.width - side) / 2).round(),
      y: ((decoded.height - side) / 2).round(),
      width: side,
      height: side,
    );

    final resized = cropped.width > 1024 || cropped.height > 1024
        ? img.copyResize(cropped, width: 1024, height: 1024)
        : cropped;

    var quality = 88;
    var output = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    while (output.lengthInBytes > targetBytes && quality > 58) {
      quality -= 10;
      output = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    }

    return PreparedProfilePhoto(
      bytes: output,
      mimeType: 'image/jpeg',
      storagePath: '$userId/profile.jpg',
    );
  }
}
