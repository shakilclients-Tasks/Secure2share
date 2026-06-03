import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// shakils projects this
import '../main.dart';
import '../models/secure_detail.dart';
import '../utils/format_utils.dart';

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
            Container(
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
                    child: Icon(_iconFor(detail.type)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          detail.title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          FormatUtils.dateTimeFromMillis(
                            detail.createdAtMillis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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

  IconData _iconFor(SecureDetailType type) {
    return switch (type) {
      SecureDetailType.bank => Icons.account_balance_outlined,
      SecureDetailType.aadhaar => Icons.badge_outlined,
      SecureDetailType.pan => Icons.credit_card_outlined,
      SecureDetailType.passport => Icons.flight_takeoff_outlined,
      SecureDetailType.drivingLicense => Icons.directions_car_outlined,
      SecureDetailType.voterId => Icons.how_to_vote_outlined,
      SecureDetailType.upi => Icons.currency_rupee_outlined,
      SecureDetailType.login => Icons.key_outlined,
      SecureDetailType.address => Icons.location_on_outlined,
    };
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
