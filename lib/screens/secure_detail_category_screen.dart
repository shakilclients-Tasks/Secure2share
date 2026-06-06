import 'package:flutter/material.dart';

import '../main.dart';
import '../models/secure_detail.dart';
import '../widgets/file_tile.dart';
import 'secure_detail_details_screen.dart';
import 'secure_details_form_screen.dart';

class SecureDetailCategoryScreen extends StatefulWidget {
  const SecureDetailCategoryScreen({super.key, required this.type});

  final SecureDetailType type;

  @override
  State<SecureDetailCategoryScreen> createState() =>
      _SecureDetailCategoryScreenState();
}

class _SecureDetailCategoryScreenState
    extends State<SecureDetailCategoryScreen> {
  late Future<List<SecureDetail>> _detailsFuture;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _detailsFuture = _loadDetails();
  }

  Future<List<SecureDetail>> _loadDetails() async {
    final details = await Drive2ShareScope.of(
      context,
    ).recentFileStore.listSecureDetails();
    return details
        .where((detail) => detail.type == widget.type)
        .toList(growable: false);
  }

  Future<void> _refresh() async {
    setState(() => _detailsFuture = _loadDetails());
    await _detailsFuture;
  }

  Future<void> _createDetail() async {
    setState(() => _isCreating = true);
    try {
      final detail = await openSecureDetailsForm(context, widget.type);
      if (!mounted || detail == null) return;
      await _refresh();
      if (!mounted) return;
      _showSaveResult(detail);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SecureDetailDetailsScreen(detail: detail.detail),
        ),
      );
      await _refresh();
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _showSaveResult(SecureDetailSaveResult result) {
    final destinations = <String>[];
    final errors = <String>[];
    if (result.syncedToSheets) {
      destinations.add('Google Sheets');
    } else {
      errors.add('Sheets: ${result.sheetsError}');
    }
    if (result.detail.images.isNotEmpty) {
      if (result.imagesUploadedToDrive) {
        destinations.add('Google Drive');
      } else {
        errors.add('Drive: ${result.driveError}');
      }
    }

    final savedMessage = destinations.isEmpty
        ? 'Cloud save failed.'
        : 'Saved to ${destinations.join(' and ')}.';
    _showSnack(
      errors.isEmpty ? savedMessage : '$savedMessage ${errors.join(' ')}',
    );
  }

  Future<void> _share(SecureDetail detail) async {
    try {
      await Drive2ShareScope.of(
        context,
      ).fileImportService.shareSecureDetail(detail);
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _delete(SecureDetail detail) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete details?'),
          content: Text('Delete "${detail.title}" from this app?'),
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
      final dependencies = Drive2ShareScope.of(context);
      await dependencies.recentFileStore.deleteSecureDetail(detail.id);
      await _refresh();
      _showSnack('Deleted "${detail.title}".');
    } catch (error) {
      _showSnack('Unable to delete: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.type.title),
        actions: <Widget>[
          IconButton(
            tooltip: 'Add ${widget.type.title}',
            onPressed: _isCreating ? null : _createDetail,
            icon: _isCreating
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<SecureDetail>>(
          future: _detailsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final details = snapshot.data ?? <SecureDetail>[];
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                children: <Widget>[
                  if (details.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Text(
                        'No ${widget.type.title.toLowerCase()} saved yet.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    for (final detail in details)
                      SecureDetailTile(
                        detail: detail,
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                SecureDetailDetailsScreen(detail: detail),
                          ),
                        ),
                        onShare: () => _share(detail),
                        onDelete: () => _delete(detail),
                      ),
                ],
              ),
            );
          },
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
}
