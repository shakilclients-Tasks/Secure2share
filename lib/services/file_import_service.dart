import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/app_config.dart';
import '../models/drive_file_item.dart';
import '../models/recent_file.dart';
import '../models/secure_detail.dart';
import '../utils/mime_type_utils.dart';
import 'drive_service.dart';
import 'recent_file_store.dart';

class FileImportService {
  FileImportService({required this.config, required this.recentFileStore});

  static const MethodChannel _shareChannel = MethodChannel(
    'drive2share/share_targets',
  );

  final AppConfig config;
  final RecentFileStore recentFileStore;
  final Uuid _uuid = const Uuid();

  Future<RecentFile> createTextFile({
    required String fileName,
    required String content,
  }) async {
    final importDir = await _importsDirectory();
    final safeName = _safeFileName(_withDefaultTextExtension(fileName));
    final destination = _uniqueFile(importDir, safeName);
    await destination.writeAsString(content);

    final mimeType =
        lookupMimeType(destination.path) ??
        MimeTypeUtils.mimeFromName(destination.path);
    final now = DateTime.now().millisecondsSinceEpoch;
    final recent = RecentFile(
      id: _uuid.v4(),
      driveFileId: null,
      name: p.basename(destination.path),
      mimeType: mimeType,
      localPath: destination.path,
      sizeBytes: await destination.length(),
      modifiedAtMillis: now,
      importedAtMillis: now,
    );
    await recentFileStore.save(recent);
    return recent;
  }

  Future<RecentFile?> importFromDevice() async {
    final result = await FilePicker.pickFiles(type: FileType.any);
    final pickedFile = result?.files.single;
    final sourcePath = pickedFile?.path;
    if (pickedFile == null || sourcePath == null) return null;

    final source = File(sourcePath);
    final mimeType =
        lookupMimeType(source.path) ??
        MimeTypeUtils.mimeFromName(pickedFile.name);
    _validateMimeType(mimeType);

    final destination = await _copyIntoImports(source, pickedFile.name);
    final recent = RecentFile(
      id: _uuid.v4(),
      driveFileId: null,
      name: p.basename(destination.path),
      mimeType: mimeType,
      localPath: destination.path,
      sizeBytes: await destination.length(),
      modifiedAtMillis: DateTime.now().millisecondsSinceEpoch,
      importedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    await recentFileStore.save(recent);
    return recent;
  }

  Future<RecentFile> importFromDrive(
    DriveFileItem item,
    DriveService driveService,
  ) async {
    if (item.isFolder) {
      throw StateError('Use importFolderFromDrive() for folders.');
    }

    _validateMimeType(item.localMimeType);
    final downloaded = await driveService.downloadFile(item);
    final recent = await _saveDriveImport(item, downloaded);
    await recentFileStore.save(recent);
    return recent;
  }

  Future<List<RecentFile>> importFolderFromDrive(
    DriveFileItem folder,
    DriveService driveService,
  ) async {
    if (!folder.isFolder) {
      return <RecentFile>[await importFromDrive(folder, driveService)];
    }

    final folderFiles = await driveService.listFilesRecursively(folder);
    final imported = <RecentFile>[];
    var skipped = 0;

    for (final item in folderFiles) {
      if (!_isAllowedMimeType(item.localMimeType)) {
        skipped++;
        continue;
      }

      final downloaded = await driveService.downloadFile(item);
      final recent = await _saveDriveImport(item, downloaded);
      await recentFileStore.save(recent);
      imported.add(recent);
    }

    if (imported.isEmpty) {
      throw StateError(
        skipped > 0
            ? 'No supported files found in this folder.'
            : 'This folder is empty.',
      );
    }

    return imported;
  }

  Future<RecentFile> _saveDriveImport(
    DriveFileItem item,
    File downloaded,
  ) async {
    return RecentFile(
      id: _uuid.v4(),
      driveFileId: item.id,
      name: p.basename(downloaded.path),
      mimeType: item.localMimeType,
      localPath: downloaded.path,
      sizeBytes: await downloaded.length(),
      modifiedAtMillis: item.modifiedAt?.millisecondsSinceEpoch ?? 0,
      importedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> share(RecentFile file) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'WhatsApp and Telegram sharing is currently available on Android.',
      );
    }

    final source = File(file.localPath);
    if (!source.existsSync()) {
      throw StateError('This imported file is no longer available.');
    }

    try {
      await _shareChannel.invokeMethod<void>('shareFile', <String, Object?>{
        'path': file.localPath,
        'name': file.name,
        'mimeType': file.mimeType,
      });
    } on PlatformException catch (error) {
      throw StateError(error.message ?? 'Unable to share this file.');
    }
  }

  Future<void> syncRecentFile(RecentFile file) {
    return recentFileStore.save(file);
  }

  Future<void> deleteRecentFile(RecentFile file) async {
    await recentFileStore.delete(file.id);

    final localFile = File(file.localPath);
    if (await localFile.exists()) {
      await localFile.delete();
    }
  }

  Future<void> shareSecureDetail(
    SecureDetail detail, {
    bool maskSecrets = true,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'WhatsApp and Telegram sharing is currently available on Android.',
      );
    }

    try {
      await _shareChannel.invokeMethod<void>('shareText', <String, Object?>{
        'text': detail.toShareText(maskSecrets: maskSecrets),
        'subject': detail.title,
      });
    } on PlatformException catch (error) {
      throw StateError(error.message ?? 'Unable to share these details.');
    }
  }

  Future<File> _copyIntoImports(File source, String originalName) async {
    final importDir = await _importsDirectory();
    final destination = _uniqueFile(importDir, _safeFileName(originalName));
    return source.copy(destination.path);
  }

  Future<Directory> _importsDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'imports'));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }

  File _uniqueFile(Directory directory, String desiredName) {
    var candidate = File(p.join(directory.path, desiredName));
    if (!candidate.existsSync()) return candidate;

    final extension = p.extension(desiredName);
    final baseName = p.basenameWithoutExtension(desiredName);
    var index = 1;
    while (candidate.existsSync()) {
      candidate = File(p.join(directory.path, '$baseName ($index)$extension'));
      index++;
    }
    return candidate;
  }

  String _safeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'drive2share-file' : cleaned;
  }

  String _withDefaultTextExtension(String fileName) {
    final trimmed = fileName.trim();
    final name = trimmed.isEmpty ? 'untitled' : trimmed;
    return p.extension(name).isEmpty ? '$name.txt' : name;
  }

  void _validateMimeType(String mimeType) {
    if (!_isAllowedMimeType(mimeType)) {
      throw StateError('This file type is disabled in assets/app_config.json.');
    }
  }

  bool _isAllowedMimeType(String mimeType) {
    return config.allowedMimeTypes.isEmpty ||
        config.allowedMimeTypes.contains(mimeType);
  }
}
