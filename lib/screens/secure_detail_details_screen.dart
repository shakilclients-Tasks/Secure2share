import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// shakils projects this
import '../main.dart';
import '../models/secure_detail.dart';

class SecureDetailDetailsScreen extends StatefulWidget {
  const SecureDetailDetailsScreen({super.key, required this.detail});

  final SecureDetail detail;

  @override
  State<SecureDetailDetailsScreen> createState() =>
      _SecureDetailDetailsScreenState();
}

class _SecureDetailDetailsScreenState extends State<SecureDetailDetailsScreen> {
  final Set<String> _visibleSecretKeys = <String>{};

  SecureDetail get detail => widget.detail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dependencies = Drive2ShareScope.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(detail.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            if (detail.needsAttention) ...<Widget>[
              _AttentionPanel(detail: detail),
              const SizedBox(height: 16),
            ],
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                children: <Widget>[
                  for (final entry in detail.fields.entries) ...<Widget>[
                    _DetailFieldRow(
                      label: SecureDetail.labelFor(entry.key),
                      value: entry.value,
                      isSecret: SecureDetail.isSecretField(entry.key),
                      isVisible: _visibleSecretKeys.contains(entry.key),
                      onToggleVisibility: () => _toggleSecret(entry.key),
                      onCopy: () => _copyValue(
                        SecureDetail.labelFor(entry.key),
                        entry.value,
                      ),
                    ),
                    if (entry.key != detail.fields.keys.last)
                      Divider(color: colorScheme.outlineVariant),
                  ],
                ],
              ),
            ),
            if (detail.images.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                'Document images',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      for (final image in detail.images)
                        SizedBox(
                          width: width,
                          child: _SecureImageCard(
                            image: image,
                            onTap: () => _showImage(image),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _share(maskSecrets: true),
              icon: const Icon(Icons.visibility_off_outlined),
              label: const Text('Safe share'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _confirmFullShare(dependencies),
              icon: const Icon(Icons.warning_amber_outlined),
              label: Text(
                '${dependencies.config.sharing.shareButtonText} full',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleSecret(String key) {
    setState(() {
      if (_visibleSecretKeys.contains(key)) {
        _visibleSecretKeys.remove(key);
      } else {
        _visibleSecretKeys.add(key);
      }
    });
  }

  Future<void> _copyValue(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied.')));
  }

  Future<void> _confirmFullShare(AppDependencies dependencies) async {
    final shouldShare = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Share full details?'),
          content: const Text('Secret values will be visible in the message.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.ios_share_outlined),
              label: const Text('Share'),
            ),
          ],
        );
      },
    );
    if (shouldShare == true) {
      await _share(maskSecrets: false);
    }
  }

  Future<void> _share({required bool maskSecrets}) async {
    try {
      await Drive2ShareScope.of(
        context,
      ).fileImportService.shareSecureDetail(detail, maskSecrets: maskSecrets);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showImage(SecureDetailImage image) {
    final imageBytes = _loadImageBytes(image);
    return showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  title: Text(image.side.label),
                  trailing: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Flexible(
                  child: FutureBuilder<Uint8List>(
                    future: imageBytes,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final bytes = snapshot.data;
                      if (bytes == null) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              snapshot.error?.toString() ??
                                  'Unable to load this image.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      return InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4,
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Uint8List> _loadImageBytes(SecureDetailImage image) async {
    final driveFileId = image.driveFileId;
    if (driveFileId != null && driveFileId.isNotEmpty) {
      return Drive2ShareScope.of(
        context,
      ).driveService.downloadSecureDetailImage(driveFileId);
    }

    if (image.localPath.isNotEmpty) {
      return File(image.localPath).readAsBytes();
    }
    throw StateError('This image is not available in Google Drive.');
  }
}

class _SecureImageCard extends StatelessWidget {
  const _SecureImageCard({required this.image, required this.onTap});

  final SecureDetailImage image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 1.25,
              child: ColoredBox(
                color: colorScheme.surfaceContainerHigh,
                child: Icon(
                  image.isUploadedToDrive
                      ? Icons.cloud_outlined
                      : Icons.broken_image_outlined,
                  size: 42,
                  color: image.isUploadedToDrive
                      ? colorScheme.primary
                      : colorScheme.error,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      image.side.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    image.isUploadedToDrive
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    size: 19,
                    color: image.isUploadedToDrive
                        ? colorScheme.primary
                        : colorScheme.error,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttentionPanel extends StatelessWidget {
  const _AttentionPanel({required this.detail});

  final SecureDetail detail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final days = detail.daysUntilExpiry;
    final message = detail.hasEmptyField
        ? 'Some fields are empty.'
        : detail.isExpired
        ? 'This detail is expired.'
        : days != null
        ? 'Expires in $days days.'
        : 'Check this detail.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.privacy_tip_outlined, color: colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailFieldRow extends StatelessWidget {
  const _DetailFieldRow({
    required this.label,
    required this.value,
    required this.isSecret,
    required this.isVisible,
    required this.onToggleVisibility,
    required this.onCopy,
  });

  final String label;
  final String value;
  final bool isSecret;
  final bool isVisible;
  final VoidCallback onToggleVisibility;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayValue = isSecret && !isVisible
        ? SecureDetail.maskedValue(value)
        : value;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              displayValue,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 4),
          if (isSecret)
            IconButton(
              tooltip: isVisible ? 'Hide' : 'Show',
              visualDensity: VisualDensity.compact,
              onPressed: onToggleVisibility,
              icon: Icon(
                isVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          IconButton(
            tooltip: 'Copy',
            visualDensity: VisualDensity.compact,
            onPressed: onCopy,
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
    );
  }
}
