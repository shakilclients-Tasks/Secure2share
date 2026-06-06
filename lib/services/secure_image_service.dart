import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/secure_detail.dart';

class SelectedSecureImage {
  const SelectedSecureImage({
    required this.side,
    required this.sourcePath,
    required this.originalName,
  });

  final SecureDetailImageSide side;
  final String sourcePath;
  final String originalName;
}

class SecureImageService {
  const SecureImageService();

  Future<List<SecureDetailImage>> prepareImages({
    required List<SelectedSecureImage> selectedImages,
  }) async {
    if (selectedImages.isEmpty) return const <SecureDetailImage>[];

    final preparedImages = <SecureDetailImage>[];
    for (final selected in selectedImages) {
      final source = File(selected.sourcePath);
      if (!await source.exists()) {
        throw StateError('${selected.side.label} could not be read.');
      }

      final extension = _safeExtension(
        selected.originalName,
        selected.sourcePath,
      );
      final fileName = '${selected.side.value}$extension';
      preparedImages.add(
        SecureDetailImage(
          side: selected.side,
          localPath: source.path,
          fileName: fileName,
          mimeType: lookupMimeType(source.path) ?? 'application/octet-stream',
        ),
      );
    }
    return preparedImages;
  }

  Future<void> purgeLegacyLocalImages() async {
    try {
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(
        p.join(documents.path, 'secure_detail_images'),
      );
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // Cleanup can be retried on the next app start.
    }
  }

  String _safeExtension(String originalName, String sourcePath) {
    final extension = p.extension(originalName).isNotEmpty
        ? p.extension(originalName)
        : p.extension(sourcePath);
    final cleaned = extension.replaceAll(RegExp(r'[^A-Za-z0-9.]'), '');
    return cleaned.isEmpty ? '.jpg' : cleaned.toLowerCase();
  }
}
