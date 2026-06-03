import 'package:flutter/material.dart';

import '../main.dart';
import '../models/secure_detail.dart';
import '../widgets/file_tile.dart';
import 'secure_detail_details_screen.dart';
import 'secure_details_form_screen.dart';

class RecentFilesScreen extends StatefulWidget {
  const RecentFilesScreen({super.key});

  @override
  State<RecentFilesScreen> createState() => _RecentFilesScreenState();
}

class _RecentFilesScreenState extends State<RecentFilesScreen> {
  late Future<List<SecureDetail>> _detailsFuture;
  bool _isCreating = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _detailsFuture = Drive2ShareScope.of(
      context,
    ).recentFileStore.listSecureDetails();
  }

  Future<void> _refresh() async {
    setState(
      () => _detailsFuture = Drive2ShareScope.of(
        context,
      ).recentFileStore.listSecureDetails(),
    );
    await _detailsFuture;
  }

  Future<void> _createFile() async {
    setState(() => _isCreating = true);
    try {
      final detail = await openSecureDetailsCreator(context);
      if (!mounted || detail == null) return;
      await _refresh();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SecureDetailDetailsScreen(detail: detail),
        ),
      );
      await _refresh();
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _share(SecureDetail detail) async {
    try {
      await Drive2ShareScope.of(
        context,
      ).fileImportService.shareSecureDetail(detail);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _delete(SecureDetail detail) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete recent file?'),
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
      await Drive2ShareScope.of(
        context,
      ).recentFileStore.deleteSecureDetail(detail.id);
      await _refresh();
      _showSnack('Deleted "${detail.title}".');
    } catch (error) {
      _showSnack('Unable to delete: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = Drive2ShareScope.of(context).config.screens;
    return Scaffold(
      appBar: AppBar(title: Text(config.recentTitle)),
      floatingActionButton: FloatingActionButton(
        shape: const CircleBorder(),
        tooltip: 'Add secure details',
        onPressed: _isCreating ? null : _createFile,
        child: _isCreating
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
      ),
      body: SafeArea(
        child: FutureBuilder<List<SecureDetail>>(
          future: _detailsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final allDetails = snapshot.data ?? <SecureDetail>[];
            final details = _filterDetails(allDetails);
            if (allDetails.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(config.recentEmptyText),
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  TextField(
                    onChanged: (value) => setState(() => _query = value),
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_outlined),
                      hintText: 'Search secure details',
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (details.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No matching details.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
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

  List<SecureDetail> _filterDetails(List<SecureDetail> details) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return details;
    return details
        .where((detail) => detail.searchableText.contains(query))
        .toList();
  }
}
