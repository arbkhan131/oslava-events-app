import 'dart:typed_data';

class PreparedProfilePhoto {
  const PreparedProfilePhoto({
    required this.bytes,
    required this.mimeType,
    required this.storagePath,
  });

  final Uint8List bytes;
  final String mimeType;
  final String storagePath;
}
