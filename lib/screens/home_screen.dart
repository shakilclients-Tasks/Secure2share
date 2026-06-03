import 'package:flutter/material.dart';

import '../main.dart';
import '../models/secure_detail.dart';
import '../widgets/file_tile.dart';
import 'recent_files_screen.dart';
import 'secure_detail_details_screen.dart';
import 'secure_details_form_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<SecureDetail>> _recentDetails;

  @override
  void initState() {
    super.initState();
    _recentDetails = _loadRecentDetails();
  }

  Future<List<SecureDetail>> _loadRecentDetails() {
    return Drive2ShareScope.of(context).recentFileStore.listSecureDetails();
  }

  void _refreshRecentDetails() {
    setState(() => _recentDetails = _loadRecentDetails());
  }

  Future<void> _openMyFiles() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RecentFilesScreen()));
    if (mounted) _refreshRecentDetails();
  }

  Future<void> _openSecureDetailsCreator() async {
    final detail = await openSecureDetailsCreator(context);
    if (!mounted || detail == null) return;
    _refreshRecentDetails();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SecureDetailDetailsScreen(detail: detail),
      ),
    );
    if (mounted) _refreshRecentDetails();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = Drive2ShareScope.of(context);
    final config = dependencies.config.home;
    final colorScheme = Theme.of(context).colorScheme;
    final greeting = _homeGreeting(dependencies);

    return Scaffold(
      appBar: AppBar(title: Text(dependencies.config.appName)),
      floatingActionButton: FloatingActionButton(
        shape: const CircleBorder(),
        tooltip: 'Add secure details',
        onPressed: _openSecureDetailsCreator,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _refreshRecentDetails(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 96),
            children: <Widget>[
              Text(
                greeting,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 22),
              _PrimaryActionPanel(onCreate: _openSecureDetailsCreator),
              const SizedBox(height: 18),
              _DashboardButton(
                icon: Icons.history_outlined,
                label: config.actions['recent']?.text ?? 'Recent',
                onPressed: _openMyFiles,
              ),
              const SizedBox(height: 18),
              FutureBuilder<List<SecureDetail>>(
                future: _recentDetails,
                builder: (context, snapshot) {
                  return _SecurityHealthPanel(
                    details: snapshot.data ?? <SecureDetail>[],
                    isLoading: snapshot.connectionState != ConnectionState.done,
                  );
                },
              ),
              const SizedBox(height: 24),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      config.recentSectionTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _openMyFiles,
                    child: Text(config.viewAllText),
                  ),
                ],
              ),
              FutureBuilder<List<SecureDetail>>(
                future: _recentDetails,
                builder: (context, snapshot) {
                  final details = snapshot.data ?? <SecureDetail>[];
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final recentDetails = details.take(4).toList();
                  if (recentDetails.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Text(
                        config.emptyRecentText,
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return Column(
                    children: recentDetails
                        .map(
                          (detail) => SecureDetailTile(
                            detail: detail,
                            onOpen: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    SecureDetailDetailsScreen(detail: detail),
                              ),
                            ),
                            onShare: () => _share(detail),
                            onDelete: () => _deleteSecureDetail(detail),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _homeGreeting(AppDependencies dependencies) {
    final user = dependencies.authService.currentUser;
    final displayName = user?.displayName?.trim();
    final email = user?.email.trim();
    final accountName = displayName != null && displayName.isNotEmpty
        ? displayName
        : email != null && email.isNotEmpty
        ? email
        : 'User';
    return 'Hi $accountName';
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

  Future<void> _deleteSecureDetail(SecureDetail detail) async {
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
      await Drive2ShareScope.of(
        context,
      ).recentFileStore.deleteSecureDetail(detail.id);
      _refreshRecentDetails();
      _showSnack('Deleted "${detail.title}".');
    } catch (error) {
      _showSnack('Unable to delete: $error');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SecurityHealthPanel extends StatelessWidget {
  const _SecurityHealthPanel({required this.details, required this.isLoading});

  final List<SecureDetail> details;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final total = details.length;
    final protectedFields = details.fold<int>(
      0,
      (sum, detail) => sum + detail.secretFieldCount,
    );
    final attentionCount = details
        .where((detail) => detail.needsAttention)
        .length;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.health_and_safety_outlined,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Secure health',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (isLoading)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _HealthPill(
                icon: Icons.folder_special_outlined,
                label: '$total saved',
              ),
              _HealthPill(
                icon: Icons.visibility_off_outlined,
                label: '$protectedFields protected',
              ),
              _HealthPill(
                icon: attentionCount == 0
                    ? Icons.verified_user_outlined
                    : Icons.notification_important_outlined,
                label: attentionCount == 0
                    ? 'No alerts'
                    : '$attentionCount alerts',
                isWarning: attentionCount > 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthPill extends StatelessWidget {
  const _HealthPill({
    required this.icon,
    required this.label,
    this.isWarning = false,
  });

  final IconData icon;
  final String label;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isWarning ? colorScheme.error : colorScheme.primary;
    final background = isWarning
        ? colorScheme.errorContainer.withValues(alpha: 0.44)
        : colorScheme.primaryContainer.withValues(alpha: 0.48);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PrimaryActionPanel extends StatelessWidget {
  const _PrimaryActionPanel({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 28,
            backgroundColor: colorScheme.primaryContainer,
            foregroundColor: colorScheme.onPrimaryContainer,
            child: const Icon(Icons.lock_outline),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Secure details',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filled(
            tooltip: 'Add',
            onPressed: onCreate,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _DashboardButton extends StatelessWidget {
  const _DashboardButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
