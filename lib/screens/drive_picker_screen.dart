import 'package:flutter/material.dart';
// Drive Picker Screen Updated
import '../main.dart';
import '../models/app_config.dart';
import '../models/drive_file_item.dart';
import '../models/drive_folder.dart';
import '../widgets/file_tile.dart';
import 'file_preview_screen.dart';

class DrivePickerScreen extends StatefulWidget {
  const DrivePickerScreen({super.key});

  @override
  State<DrivePickerScreen> createState() => _DrivePickerScreenState();
}

class _DrivePickerScreenState extends State<DrivePickerScreen> {
  static const String _folderSettingKey = 'drive_folder_name';

  late Future<List<DriveFileItem>> _filesFuture;
  List<DriveFileItem> _allFiles = <DriveFileItem>[];
  String _query = '';
  DriveFolder? _folder;
  final List<DriveFolder> _folderStack = <DriveFolder>[];
  String? _folderName;
  bool _folderMissing = false;
  bool _isCreatingFolder = false;
  String? _importingFileId;

  @override
  void initState() {
    super.initState();
    _filesFuture = _loadFiles();
  }

  Future<List<DriveFileItem>> _loadFiles() async {
    final dependencies = Drive2ShareScope.of(context);
    final folderConfig = await _currentFolderConfig();
    if (!mounted) return <DriveFileItem>[];

    setState(() => _folderName = folderConfig.name);
    final folder = await dependencies.driveService.findFolder(folderConfig);

    if (!mounted) return <DriveFileItem>[];

    if (folder == null) {
      setState(() {
        _folder = null;
        _folderName = folderConfig.name;
        _folderMissing = true;
        _allFiles = <DriveFileItem>[];
      });
      return <DriveFileItem>[];
    }

    return _loadFilesForFolder(folder, resetStack: true);
  }

  Future<DriveFolderConfig> _currentFolderConfig() async {
    final dependencies = Drive2ShareScope.of(context);
    final savedName = await dependencies.recentFileStore.getSetting(
      _folderSettingKey,
    );
    final trimmedName = savedName?.trim();
    if (trimmedName == null || trimmedName.isEmpty) {
      return dependencies.config.driveFolder;
    }
    return dependencies.config.driveFolder.copyWith(name: trimmedName);
  }

  Future<List<DriveFileItem>> _loadFilesForFolder(
    DriveFolder folder, {
    bool pushFolder = false,
    bool resetStack = false,
  }) async {
    final dependencies = Drive2ShareScope.of(context);
    if (mounted) {
      setState(() {
        _folder = folder;
        _folderName = folder.name;
        _folderMissing = false;
        if (resetStack) {
          _folderStack
            ..clear()
            ..add(folder);
        } else if (pushFolder) {
          _folderStack.add(folder);
        } else if (_folderStack.isEmpty) {
          _folderStack.add(folder);
        }
      });
    }

    final files = await dependencies.driveService.listItemsInFolder(folder.id);
    if (mounted) setState(() => _allFiles = files);
    return files;
  }

  Future<bool?> _confirmCreateFolder(String folderName) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create folder?'),
          content: Text(
            'The folder "$folderName" was not found in your Google Drive. Do you want to create it now?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _requestFolderName() async {
    final controller = TextEditingController(
      text: _folderName ?? Drive2ShareScope.of(context).config.driveFolder.name,
    );

    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set Drive folder'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Folder name',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Set'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (name == null || name.trim().isEmpty) return null;
    return name.trim();
  }

  List<DriveFileItem> get _visibleFiles {
    if (_query.trim().isEmpty) return _allFiles;
    final query = _query.toLowerCase();
    return _allFiles.where((file) {
      return file.name.toLowerCase().contains(query) ||
          file.localMimeType.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _refresh() async {
    setState(() => _filesFuture = _loadFiles());
    await _filesFuture;
  }

  Future<void> _openFolder(DriveFileItem folder) async {
    setState(
      () => _filesFuture = _loadFilesForFolder(
        DriveFolder(id: folder.id, name: folder.name),
        pushFolder: true,
      ),
    );
    await _filesFuture;
  }

  Future<void> _goBackFolder() async {
    if (_folderStack.length <= 1) return;
    final parent = _folderStack[_folderStack.length - 2];
    setState(() {
      _folderStack.removeLast();
      _filesFuture = _loadFilesForFolder(parent);
    });
    await _filesFuture;
  }

  Future<void> _handleAddFolder() async {
    if (_isCreatingFolder) return;

    final dependencies = Drive2ShareScope.of(context);
    final folderConfig = await _currentFolderConfig();
    if (!mounted) return;
    final existingFolder = _folder;
    if (existingFolder != null && !_folderMissing) {
      _showSnack('Folder "${existingFolder.name}" is already ready.');
      return;
    }

    final shouldCreate = await _confirmCreateFolder(folderConfig.name);
    if (shouldCreate != true || !mounted) return;

    setState(() => _isCreatingFolder = true);
    try {
      final folder = await dependencies.driveService.createFolder(folderConfig);
      if (!mounted) return;
      setState(
        () => _filesFuture = _loadFilesForFolder(folder, resetStack: true),
      );
      _showSnack('Folder "${folder.name}" created.');
      await _filesFuture;
    } catch (error) {
      if (mounted) _showSnack('Unable to create folder: $error');
    } finally {
      if (mounted) setState(() => _isCreatingFolder = false);
    }
  }

  Future<void> _setFolder() async {
    final folderName = await _requestFolderName();
    if (folderName == null || !mounted) return;

    await Drive2ShareScope.of(
      context,
    ).recentFileStore.setSetting(_folderSettingKey, folderName);
    setState(() {
      _query = '';
      _folder = null;
      _folderStack.clear();
      _folderName = folderName;
      _folderMissing = false;
      _allFiles = <DriveFileItem>[];
      _filesFuture = _loadFiles();
    });
  }

  Future<void> _deleteCurrentFolder() async {
    final folder = _folder;
    if (folder == null) {
      _showSnack('No Drive folder is selected.');
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Drive folder?'),
          content: Text(
            'Move "${folder.name}" and its contents to Google Drive trash?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true || !mounted) return;

    try {
      await Drive2ShareScope.of(context).driveService.trashFolder(folder.id);
      if (!mounted) return;
      _showSnack('Folder "${folder.name}" moved to trash.');
      if (_folderStack.length > 1) {
        _folderStack.removeLast();
        final parent = _folderStack.last;
        setState(() => _filesFuture = _loadFilesForFolder(parent));
        await _filesFuture;
      } else {
        setState(() {
          _folder = null;
          _folderStack.clear();
          _folderMissing = true;
          _allFiles = <DriveFileItem>[];
          _filesFuture = Future<List<DriveFileItem>>.value(<DriveFileItem>[]);
        });
      }
    } catch (error) {
      _showSnack('Unable to delete folder: $error');
    }
  }

  Future<void> _importItem(DriveFileItem item) async {
    setState(() => _importingFileId = item.id);
    try {
      final dependencies = Drive2ShareScope.of(context);
      if (item.isFolder) {
        final imported = await dependencies.fileImportService
            .importFolderFromDrive(item, dependencies.driveService);
        if (!mounted) return;
        _showSnack('Imported ${imported.length} file(s) from "${item.name}".');
        return;
      }

      final recent = await dependencies.fileImportService.importFromDrive(
        item,
        dependencies.driveService,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FilePreviewScreen(file: recent),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyDriveError(error))));
      }
    } finally {
      if (mounted) setState(() => _importingFileId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = Drive2ShareScope.of(context).config.screens;
    return Scaffold(
      appBar: AppBar(
        leading: _folderStack.length > 1
            ? IconButton(
                tooltip: 'Back folder',
                onPressed: _goBackFolder,
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        title: Text(config.filesTitle),
        actions: <Widget>[
          IconButton(
            tooltip: 'Set folder',
            onPressed: _setFolder,
            icon: const Icon(Icons.drive_file_rename_outline),
          ),
          IconButton(
            tooltip: 'Delete folder',
            onPressed: _folder == null ? null : _deleteCurrentFolder,
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        shape: const CircleBorder(),
        tooltip: 'Create Drive folder',
        onPressed: _isCreatingFolder ? null : _handleAddFolder,
        child: _isCreatingFolder
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.create_new_folder_outlined),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _FolderLabel(folderName: _folderPathLabel),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_outlined),
                      labelText: 'Search folder files',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<DriveFileItem>>(
                future: _filesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _CenteredMessage(
                      message: _friendlyDriveError(snapshot.error),
                    );
                  }

                  if (_folderMissing) {
                    return _MissingFolderMessage(
                      folderName:
                          _folderName ??
                          Drive2ShareScope.of(context).config.driveFolder.name,
                      onCreate: _handleAddFolder,
                      isCreating: _isCreatingFolder,
                    );
                  }

                  final files = _visibleFiles;
                  if (files.isEmpty) {
                    return _CenteredMessage(message: config.filesEmptyText);
                  }

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: files.length,
                      itemBuilder: (context, index) {
                        final file = files[index];
                        return DriveFileTile(
                          file: file,
                          isBusy: _importingFileId == file.id,
                          onTap: file.isFolder
                              ? () => _openFolder(file)
                              : () => _importItem(file),
                          onImport: () => _importItem(file),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? get _folderPathLabel {
    if (_folderStack.isEmpty) return _folderName;
    return _folderStack.map((folder) => folder.name).join(' / ');
  }

  String _friendlyDriveError(Object? error) {
    final text = error.toString();
    if (text.contains('insufficient_scope')) {
      return 'Google Drive permission is missing. Sign out, sign in again, and approve Drive access. Also add the full Google Drive scope in Google Cloud OAuth consent screen.';
    }
    return 'Unable to load files: $text';
  }
}

class _FolderLabel extends StatelessWidget {
  const _FolderLabel({required this.folderName});

  final String? folderName;

  @override
  Widget build(BuildContext context) {
    final configuredName = Drive2ShareScope.of(context).config.driveFolder.name;
    return Row(
      children: <Widget>[
        Icon(
          Icons.folder_outlined,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Folder: ${folderName ?? configuredName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _MissingFolderMessage extends StatelessWidget {
  const _MissingFolderMessage({
    required this.folderName,
    required this.onCreate,
    required this.isCreating,
  });

  final String folderName;
  final VoidCallback onCreate;
  final bool isCreating;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.folder_off_outlined,
              size: 60,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              'Folder "$folderName" was not found.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the folder button to create it in Google Drive.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: isCreating ? null : onCreate,
              icon: isCreating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.create_new_folder_outlined),
              label: const Text('Create folder'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
