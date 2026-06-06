import 'package:flutter/material.dart';

import '../models/drive_file_item.dart';
import '../models/recent_file.dart';
import '../models/secure_detail.dart';
import '../utils/format_utils.dart';
import '../utils/mime_type_utils.dart';

class DriveFileTile extends StatelessWidget {
  const DriveFileTile({
    super.key,
    required this.file,
    required this.onTap,
    required this.isBusy,
    this.onImport,
  });

  final DriveFileItem file;
  final VoidCallback onTap;
  final bool isBusy;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        enabled: !isBusy,
        leading: _FileIcon(mimeType: file.localMimeType, fileName: file.name),
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: isBusy
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: file.isFolder ? 'Import folder' : 'Import',
                onPressed: onImport ?? onTap,
                icon: const Icon(Icons.file_download_outlined),
              ),
        onTap: isBusy ? null : onTap,
      ),
    );
  }

  String get _subtitle {
    if (file.isFolder) {
      return 'Folder • Tap to open\nModified ${FormatUtils.dateTime(file.modifiedAt)}';
    }
    return '${file.localMimeType} • ${FormatUtils.fileSize(file.sizeBytes)}\nModified ${FormatUtils.dateTime(file.modifiedAt)}';
  }
}

class RecentFileTile extends StatelessWidget {
  const RecentFileTile({
    super.key,
    required this.file,
    required this.onOpen,
    required this.onShare,
    this.onDelete,
  });

  final RecentFile file;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: _FileIcon(mimeType: file.mimeType, fileName: file.name),
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${file.mimeType} • ${FormatUtils.fileSize(file.sizeBytes)}\nImported ${FormatUtils.dateTimeFromMillis(file.importedAtMillis)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: 'Share',
              onPressed: onShare,
              icon: const Icon(Icons.ios_share_outlined),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        onTap: onOpen,
      ),
    );
  }
}

class SecureDetailTile extends StatelessWidget {
  const SecureDetailTile({
    super.key,
    required this.detail,
    required this.onOpen,
    required this.onShare,
    this.onDelete,
  });

  final SecureDetail detail;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: _SecureDetailIcon(type: detail.type),
        title: Text(detail.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: 'Share',
              onPressed: onShare,
              icon: const Icon(Icons.ios_share_outlined),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        onTap: onOpen,
      ),
    );
  }

  String get _subtitle {
    final name = _displayName;
    final savedAt = FormatUtils.dateTimeFromMillis(detail.createdAtMillis);
    if (name == null || name.isEmpty) return 'Saved $savedAt';
    return '$name\nSaved $savedAt';
  }

  String? get _displayName {
    for (final key in <String>[
      'name',
      'fullName',
      'cardHolderName',
      'serviceName',
      'bankName',
      'username',
    ]) {
      final value = detail.fields[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}

class _SecureDetailIcon extends StatelessWidget {
  const _SecureDetailIcon({required this.type});

  final SecureDetailType type;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = switch (type) {
      SecureDetailType.bank => Icons.account_balance_outlined,
      SecureDetailType.aadhaar => Icons.badge_outlined,
      SecureDetailType.pan => Icons.assignment_ind_outlined,
      SecureDetailType.passport => Icons.flight_takeoff_outlined,
      SecureDetailType.drivingLicense => Icons.directions_car_outlined,
      SecureDetailType.voterId => Icons.how_to_vote_outlined,
      SecureDetailType.upi => Icons.currency_rupee_outlined,
      SecureDetailType.login => Icons.key_outlined,
      SecureDetailType.password => Icons.password_outlined,
      SecureDetailType.nationalId => Icons.badge_outlined,
      SecureDetailType.taxId => Icons.receipt_long_outlined,
      SecureDetailType.socialSecurity => Icons.security_outlined,
      SecureDetailType.healthInsurance => Icons.medical_information_outlined,
      SecureDetailType.residencePermit => Icons.assignment_outlined,
      SecureDetailType.debitCard => Icons.account_balance_wallet_outlined,
      SecureDetailType.creditCard => Icons.credit_card_outlined,
      SecureDetailType.address => Icons.location_on_outlined,
    };
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: colorScheme.primary),
    );
  }
}

class _FileIcon extends StatelessWidget {
  const _FileIcon({required this.mimeType, required this.fileName});

  final String mimeType;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        MimeTypeUtils.iconFor(mimeType, fileName),
        color: colorScheme.primary,
      ),
    );
  }
}
