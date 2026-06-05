import 'dart:io';
import 'dart:typed_data';

import 'package:_discoveryapis_commons/_discoveryapis_commons.dart' as commons;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_config.dart';
import '../models/drive_file_item.dart';
import '../models/drive_folder.dart';
import '../models/secure_detail.dart';
import '../utils/mime_type_utils.dart';
import 'auth_service.dart';

class DriveService {
  DriveService(this._authService);

  final AuthService _authService;
  final Map<String, Future<DriveFolder>> _folderFutures =
      <String, Future<DriveFolder>>{};

  Future<DriveFolder?> findFolder(DriveFolderConfig config) async {
    final client = await _authService.authClient();
    try {
      final api = drive.DriveApi(client);
      final response = await api.files.list(
        q: [
          'trashed = false',
          "mimeType = 'application/vnd.google-apps.folder'",
          "name = ${_queryLiteral(config.name)}",
          "${_queryLiteral(config.parentId)} in parents",
        ].join(' and '),
        orderBy: 'modifiedTime desc',
        pageSize: 1,
        spaces: 'drive',
        $fields: 'files(id,name)',
      );
      final folders =
          response.files?.where((file) => file.id != null).toList() ??
          <drive.File>[];
      final folder = folders.isEmpty ? null : folders.first;
      return folder == null ? null : DriveFolder.fromDriveFile(folder);
    } finally {
      client.close();
    }
  }

  Future<DriveFolder> createFolder(DriveFolderConfig config) async {
    final client = await _authService.authClient();
    try {
      final api = drive.DriveApi(client);
      final created = await api.files.create(
        drive.File()
          ..name = config.name
          ..mimeType = 'application/vnd.google-apps.folder'
          ..parents = <String>[config.parentId],
        $fields: 'id,name',
      );
      if (created.id == null) {
        throw StateError('Google Drive did not return the new folder ID.');
      }
      return DriveFolder.fromDriveFile(created);
    } finally {
      client.close();
    }
  }

  Future<DriveImageUploadResult> uploadSecureDetailImages({
    required DriveFolderConfig config,
    required SecureDetail detail,
  }) async {
    return _uploadSecureDetailImages(
      config: config,
      detail: detail,
      allowAuthorizationRetry: true,
    );
  }

  Future<DriveImageUploadResult> _uploadSecureDetailImages({
    required DriveFolderConfig config,
    required SecureDetail detail,
    required bool allowAuthorizationRetry,
  }) async {
    final client = await _authService.authClient();
    try {
      final api = drive.DriveApi(client);
      final folder = await _findOrCreateDetailFolder(api, config, detail);
      final attempts = await Future.wait(
        detail.images.map(
          (image) => _uploadSecureDetailImage(
            api: api,
            folderId: folder.id,
            detail: detail,
            image: image,
          ),
        ),
      );
      final uploadedImages = attempts
          .map((attempt) => attempt.image)
          .toList(growable: false);
      final firstError = attempts
          .map((attempt) => attempt.error)
          .whereType<String>()
          .firstOrNull;

      return DriveImageUploadResult(images: uploadedImages, error: firstError);
    } catch (error) {
      if (allowAuthorizationRetry && AuthService.isInsufficientScope(error)) {
        await _authService.reauthorize();
        return _uploadSecureDetailImages(
          config: config,
          detail: detail,
          allowAuthorizationRetry: false,
        );
      }
      return DriveImageUploadResult(
        images: detail.images,
        error: AuthService.friendlyGoogleError(error, service: 'Google Drive'),
      );
    } finally {
      client.close();
    }
  }

  Future<_DriveImageUploadAttempt> _uploadSecureDetailImage({
    required drive.DriveApi api,
    required String folderId,
    required SecureDetail detail,
    required SecureDetailImage image,
  }) async {
    if (image.isUploadedToDrive) {
      return _DriveImageUploadAttempt(image: image);
    }

    try {
      final localFile = File(image.localPath);
      if (!await localFile.exists()) {
        throw StateError('${image.side.label} is missing from this device.');
      }

      final extension = p.extension(image.fileName);
      final driveName = '${image.side.value}$extension';
      final created = await api.files.create(
        drive.File()
          ..name = driveName
          ..mimeType = image.mimeType
          ..parents = <String>[folderId]
          ..appProperties = <String, String>{
            'digitalWalletDetailId': detail.id,
            'digitalWalletImageSide': image.side.value,
          },
        uploadMedia: commons.Media(
          localFile.openRead(),
          await localFile.length(),
          contentType: image.mimeType,
        ),
        $fields: 'id,name,webViewLink',
      );

      final fileId = created.id;
      if (fileId == null || fileId.isEmpty) {
        throw StateError(
          'Google Drive did not return an ID for ${image.side.label}.',
        );
      }
      return _DriveImageUploadAttempt(
        image: image.copyWith(
          localPath: '',
          driveFileId: fileId,
          driveWebViewLink: created.webViewLink,
        ),
      );
    } catch (error) {
      if (AuthService.isInsufficientScope(error)) rethrow;
      return _DriveImageUploadAttempt(
        image: image,
        error: '${image.side.label}: $error',
      );
    }
  }

  Future<Uint8List> downloadSecureDetailImage(String fileId) {
    return _downloadSecureDetailImage(fileId, allowAuthorizationRetry: true);
  }

  Future<Uint8List> _downloadSecureDetailImage(
    String fileId, {
    required bool allowAuthorizationRetry,
  }) async {
    final client = await _authService.authClient();
    try {
      final api = drive.DriveApi(client);
      final media =
          await api.files.get(
                fileId,
                downloadOptions: commons.DownloadOptions.fullMedia,
              )
              as commons.Media;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in media.stream) {
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } catch (error) {
      if (allowAuthorizationRetry && AuthService.isInsufficientScope(error)) {
        await _authService.reauthorize();
        return _downloadSecureDetailImage(
          fileId,
          allowAuthorizationRetry: false,
        );
      }
      throw StateError(
        AuthService.friendlyGoogleError(error, service: 'Google Drive image'),
      );
    } finally {
      client.close();
    }
  }

  Future<void> trashFolder(String folderId) async {
    final client = await _authService.authClient();
    try {
      final api = drive.DriveApi(client);
      await api.files.update(
        drive.File()..trashed = true,
        folderId,
        $fields: 'id,trashed',
      );
    } finally {
      client.close();
    }
  }

  Future<List<DriveFileItem>> listItemsInFolder(String folderId) async {
    final client = await _authService.authClient();
    try {
      final api = drive.DriveApi(client);
      return _listItems(api, folderId);
    } finally {
      client.close();
    }
  }

  Future<List<DriveFileItem>> listFilesRecursively(DriveFileItem folder) async {
    if (!folder.isFolder) {
      return <DriveFileItem>[folder];
    }

    final client = await _authService.authClient();
    try {
      final api = drive.DriveApi(client);
      final files = <DriveFileItem>[];
      await _collectFiles(
        api,
        folderId: folder.id,
        folderPath: <String>[folder.name],
        output: files,
      );
      return files;
    } finally {
      client.close();
    }
  }

  Future<File> downloadFile(DriveFileItem file) async {
    if (file.isFolder) {
      throw StateError('Folders must be imported recursively.');
    }

    final client = await _authService.authClient();
    try {
      final api = drive.DriveApi(client);
      final importDir = await _importsDirectory(file.relativeFolderPath);
      final destination = _uniqueFile(
        importDir,
        _safeFileName(file.name, MimeTypeUtils.extensionFor(file.mimeType)),
      );

      final commons.Media? media;
      if (file.isGoogleWorkspaceFile) {
        media = await api.files.export(
          file.id,
          MimeTypeUtils.exportMimeType(file.mimeType),
          downloadOptions: commons.DownloadOptions.fullMedia,
        );
      } else {
        media =
            await api.files.get(
                  file.id,
                  downloadOptions: commons.DownloadOptions.fullMedia,
                )
                as commons.Media;
      }

      if (media == null) {
        throw StateError('No downloadable content returned.');
      }

      final sink = destination.openWrite();
      await media.stream.pipe(sink);
      return destination;
    } finally {
      client.close();
    }
  }

  Future<List<DriveFileItem>> _listItems(
    drive.DriveApi api,
    String folderId,
  ) async {
    final items = <DriveFileItem>[];
    String? pageToken;

    do {
      final response = await api.files.list(
        q: [
          'trashed = false',
          "${_queryLiteral(folderId)} in parents",
        ].join(' and '),
        orderBy: 'folder,name_natural',
        pageSize: 100,
        pageToken: pageToken,
        spaces: 'drive',
        $fields: 'nextPageToken,files(id,name,mimeType,size,modifiedTime)',
      );
      items.addAll(
        response.files
                ?.where((file) => file.id != null)
                .map(DriveFileItem.fromDriveFile) ??
            const Iterable<DriveFileItem>.empty(),
      );
      pageToken = response.nextPageToken;
    } while (pageToken != null);

    return items;
  }

  Future<DriveFolder> _findOrCreateDetailFolder(
    drive.DriveApi api,
    DriveFolderConfig config,
    SecureDetail detail,
  ) async {
    final rootFolder = await _findOrCreateFolder(
      api,
      parentId: config.parentId,
      name: config.rootFolderName,
      marker: 'organization-root',
    );
    final appFolder = await _findOrCreateFolder(
      api,
      parentId: rootFolder.id,
      name: config.name,
      marker: 'digital-wallet-root',
    );
    final categoryFolder = await _findOrCreateFolder(
      api,
      parentId: appFolder.id,
      name: _safePathSegment(detail.categoryName),
      marker: 'category-${detail.type.value}',
    );
    return _findOrCreateFolder(
      api,
      parentId: categoryFolder.id,
      name: _recordFolderName(detail),
      marker: 'record-${detail.id}',
    );
  }

  Future<DriveFolder> _findOrCreateFolder(
    drive.DriveApi api, {
    required String parentId,
    required String name,
    required String marker,
  }) async {
    final cacheKey = _folderCacheKey(parentId, name);
    final cached = _folderFutures[cacheKey];
    if (cached != null) return cached;

    final pending = _loadOrCreateFolder(
      api,
      parentId: parentId,
      name: name,
      marker: marker,
    );
    _folderFutures[cacheKey] = pending;
    try {
      return await pending;
    } catch (_) {
      if (identical(_folderFutures[cacheKey], pending)) {
        _folderFutures.remove(cacheKey);
      }
      rethrow;
    }
  }

  Future<DriveFolder> _loadOrCreateFolder(
    drive.DriveApi api, {
    required String parentId,
    required String name,
    required String marker,
  }) async {
    final response = await api.files.list(
      q: [
        'trashed = false',
        "mimeType = 'application/vnd.google-apps.folder'",
        "name = ${_queryLiteral(name)}",
        "${_queryLiteral(parentId)} in parents",
      ].join(' and '),
      orderBy: 'modifiedTime desc',
      pageSize: 1,
      spaces: 'drive',
      $fields: 'files(id,name)',
    );
    final existing = response.files
        ?.where((file) => file.id?.isNotEmpty == true)
        .firstOrNull;
    if (existing != null) {
      return DriveFolder.fromDriveFile(existing);
    }

    final created = await api.files.create(
      drive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = <String>[parentId]
        ..appProperties = <String, String>{'digitalWalletFolder': marker},
      $fields: 'id,name',
    );
    if (created.id == null || created.id!.isEmpty) {
      throw StateError('Google Drive did not return the folder ID.');
    }
    return DriveFolder.fromDriveFile(created);
  }

  Future<void> _collectFiles(
    drive.DriveApi api, {
    required String folderId,
    required List<String> folderPath,
    required List<DriveFileItem> output,
  }) async {
    final items = await _listItems(api, folderId);
    for (final item in items) {
      if (item.isFolder) {
        await _collectFiles(
          api,
          folderId: item.id,
          folderPath: <String>[...folderPath, item.name],
          output: output,
        );
      } else {
        output.add(item.copyWith(relativeFolderPath: folderPath));
      }
    }
  }

  Future<Directory> _importsDirectory([
    List<String> folderPath = const <String>[],
  ]) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      p.joinAll(<String>[
        documents.path,
        'imports',
        ...folderPath.map(_safePathSegment),
      ]),
    );
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

  String _safeFileName(String name, String fallbackExtension) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final fileName = cleaned.isEmpty ? 'drive2share-file' : cleaned;
    return p.extension(fileName).isEmpty
        ? '$fileName.$fallbackExtension'
        : fileName;
  }

  String _safePathSegment(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'folder' : cleaned;
  }

  String _queryLiteral(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    return "'$escaped'";
  }

  String _folderCacheKey(String parentId, String name) {
    final account = _authService.currentUser?.id ?? 'default';
    return '$account::$parentId::$name';
  }

  String _recordFolderName(SecureDetail detail) {
    final shortId = detail.id.length <= 8
        ? detail.id
        : detail.id.substring(0, 8);
    final value = _safePathSegment('${detail.displayName} - $shortId');
    return value.length <= 120 ? value : value.substring(0, 120);
  }
}

class DriveImageUploadResult {
  const DriveImageUploadResult({required this.images, this.error});

  final List<SecureDetailImage> images;
  final String? error;

  bool get isSuccessful => error == null;
}

class _DriveImageUploadAttempt {
  const _DriveImageUploadAttempt({required this.image, this.error});

  final SecureDetailImage image;
  final String? error;
}
