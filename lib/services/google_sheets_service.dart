import 'dart:convert';

import 'package:_discoveryapis_commons/_discoveryapis_commons.dart' as commons;
import 'package:googleapis/sheets/v4.dart' as sheets;

import '../models/app_config.dart';
import '../models/secure_detail.dart';
import 'auth_service.dart';
import 'recent_file_store.dart';

class GoogleSheetsService {
  GoogleSheetsService({
    required this.config,
    required this.authService,
    required this.recentFileStore,
  });

  static const String _storedSpreadsheetIdPrefix = 'googleSheetsSpreadsheetId';
  static const String _syncedDetailIdsPrefix = 'googleSheetsSyncedDetailIds';
  static const List<String> _headers = <String>[
    'Saved At',
    'Detail ID',
    'Type',
    'Title',
    'Name',
    'Labels',
    'Values',
    'Data JSON',
  ];

  final GoogleSheetsConfig config;
  final AuthService authService;
  final RecentFileStore recentFileStore;

  Future<GoogleSheetsSyncResult> syncSavedSecureDetails() async {
    if (!config.enabled) return const GoogleSheetsSyncResult.disabled();

    if (!authService.isSignedIn) {
      await authService.signIn();
    }

    final details = await recentFileStore.listSecureDetails();
    if (details.isEmpty) return const GoogleSheetsSyncResult.empty();

    final client = await authService.authClient();
    try {
      final api = sheets.SheetsApi(client);
      final spreadsheetId = await _spreadsheetId(api);
      await _ensureSheetExists(api, spreadsheetId);
      await _ensureHeaderRow(api, spreadsheetId);

      final syncedIds = await _syncedDetailIds(spreadsheetId);
      var syncedCount = 0;
      var skippedCount = 0;

      for (final detail in details.reversed) {
        if (syncedIds.contains(detail.id)) {
          skippedCount++;
          continue;
        }

        await _appendRow(api, spreadsheetId, detail);
        syncedIds.add(detail.id);
        await _saveSyncedDetailIds(spreadsheetId, syncedIds);
        syncedCount++;
      }

      return GoogleSheetsSyncResult(
        totalCount: details.length,
        syncedCount: syncedCount,
        skippedCount: skippedCount,
      );
    } on commons.DetailedApiRequestError catch (error) {
      throw StateError(_sheetsSetupMessage(error));
    } on commons.ApiRequestError catch (error) {
      throw StateError(error.message ?? 'Google Sheets sync failed.');
    } finally {
      client.close();
    }
  }

  Future<void> appendSecureDetail(SecureDetail detail) async {
    if (!config.enabled) return;

    if (!authService.isSignedIn) {
      await authService.signIn();
    }

    final client = await authService.authClient();
    try {
      final api = sheets.SheetsApi(client);
      final spreadsheetId = await _spreadsheetId(api);
      await _ensureSheetExists(api, spreadsheetId);
      await _ensureHeaderRow(api, spreadsheetId);

      final syncedIds = await _syncedDetailIds(spreadsheetId);
      if (syncedIds.contains(detail.id)) return;

      await _appendRow(api, spreadsheetId, detail);
      syncedIds.add(detail.id);
      await _saveSyncedDetailIds(spreadsheetId, syncedIds);
    } on commons.DetailedApiRequestError catch (error) {
      throw StateError(_sheetsSetupMessage(error));
    } on commons.ApiRequestError catch (error) {
      throw StateError(error.message ?? 'Google Sheets sync failed.');
    } finally {
      client.close();
    }
  }

  Future<String> _spreadsheetId(sheets.SheetsApi api) async {
    final configuredId = _cleanSpreadsheetId(config.spreadsheetId);
    if (configuredId.isNotEmpty) return configuredId;

    final storedId = await recentFileStore.getSetting(_storedSpreadsheetIdKey);
    if (storedId != null && storedId.trim().isNotEmpty) return storedId;

    final spreadsheet = await api.spreadsheets.create(
      sheets.Spreadsheet(
        properties: sheets.SpreadsheetProperties(
          title: config.spreadsheetTitle,
        ),
        sheets: <sheets.Sheet>[
          sheets.Sheet(
            properties: sheets.SheetProperties(title: config.sheetName),
          ),
        ],
      ),
      $fields: 'spreadsheetId',
    );

    final createdId = spreadsheet.spreadsheetId;
    if (createdId == null || createdId.isEmpty) {
      throw StateError('Google Sheets did not return a spreadsheet ID.');
    }

    await recentFileStore.setSetting(_storedSpreadsheetIdKey, createdId);
    return createdId;
  }

  Future<void> _appendRow(
    sheets.SheetsApi api,
    String spreadsheetId,
    SecureDetail detail,
  ) {
    return api.spreadsheets.values.append(
      sheets.ValueRange(values: <List<Object?>>[_rowFor(detail)]),
      spreadsheetId,
      _range('A1'),
      insertDataOption: 'INSERT_ROWS',
      valueInputOption: 'USER_ENTERED',
    );
  }

  Future<void> _ensureSheetExists(
    sheets.SheetsApi api,
    String spreadsheetId,
  ) async {
    final spreadsheet = await api.spreadsheets.get(
      spreadsheetId,
      $fields: 'sheets.properties.title',
    );
    final exists =
        spreadsheet.sheets?.any(
          (sheet) => sheet.properties?.title == config.sheetName,
        ) ??
        false;
    if (exists) return;

    await api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(
        requests: <sheets.Request>[
          sheets.Request(
            addSheet: sheets.AddSheetRequest(
              properties: sheets.SheetProperties(title: config.sheetName),
            ),
          ),
        ],
      ),
      spreadsheetId,
    );
  }

  Future<void> _ensureHeaderRow(
    sheets.SheetsApi api,
    String spreadsheetId,
  ) async {
    final existing = await api.spreadsheets.values.get(
      spreadsheetId,
      _range('A1:H1'),
    );
    if (existing.values?.isNotEmpty == true) return;

    await api.spreadsheets.values.update(
      sheets.ValueRange(values: <List<Object?>>[_headers]),
      spreadsheetId,
      _range('A1:H1'),
      valueInputOption: 'RAW',
    );
  }

  List<Object?> _rowFor(SecureDetail detail) {
    final labels = detail.fields.keys.map(SecureDetail.labelFor).join('\n');
    final values = detail.fields.values.join('\n');
    return <Object?>[
      DateTime.fromMillisecondsSinceEpoch(
        detail.createdAtMillis,
      ).toIso8601String(),
      detail.id,
      detail.type.value,
      detail.title,
      detail.fields['name'] ?? detail.fields['fullName'] ?? '',
      labels,
      values,
      jsonEncode(detail.fields),
    ];
  }

  String _range(String cellRange) {
    final escapedSheetName = config.sheetName.replaceAll("'", "''");
    return "'$escapedSheetName'!$cellRange";
  }

  Future<Set<String>> _syncedDetailIds(String spreadsheetId) async {
    final jsonText = await recentFileStore.getSetting(
      _syncedDetailIdsKey(spreadsheetId),
    );
    if (jsonText == null || jsonText.trim().isEmpty) return <String>{};

    final decoded = jsonDecode(jsonText);
    if (decoded is! List<dynamic>) return <String>{};
    return decoded.whereType<String>().toSet();
  }

  Future<void> _saveSyncedDetailIds(
    String spreadsheetId,
    Set<String> syncedIds,
  ) {
    return recentFileStore.setSetting(
      _syncedDetailIdsKey(spreadsheetId),
      jsonEncode(syncedIds.toList()..sort()),
    );
  }

  String _cleanSpreadsheetId(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('AIza')) return '';
    final uri = Uri.tryParse(trimmed);
    final segments = uri?.pathSegments ?? const <String>[];
    final idIndex = segments.indexOf('d') + 1;
    if (idIndex > 0 && idIndex < segments.length) {
      return segments[idIndex];
    }
    final match = RegExp(r'/d/([^/]+)').firstMatch(trimmed);
    if (match != null) return match.group(1) ?? '';
    if (trimmed.startsWith('http')) return '';
    return trimmed;
  }

  String _sheetsSetupMessage(commons.DetailedApiRequestError error) {
    final message = error.message ?? '';
    if (error.status == 403 &&
        message.contains('Google Sheets API has not been used')) {
      return 'Google Sheets API is disabled for project to-share-37301. Open Google Cloud Console > APIs & Services > Library > Google Sheets API > Enable, wait 2-5 minutes, then try again.';
    }
    if (error.status == 403) {
      return 'Google Sheets permission denied. Enable Google Sheets API, add your Gmail as an OAuth test user, and allow Sheets permission during Google login.';
    }
    return message.isEmpty
        ? 'Google Sheets sync failed.'
        : 'Google Sheets sync failed: $message';
  }

  String get _storedSpreadsheetIdKey {
    return '$_storedSpreadsheetIdPrefix:${_accountKey()}';
  }

  String _syncedDetailIdsKey(String spreadsheetId) {
    return '$_syncedDetailIdsPrefix:${_accountKey()}:$spreadsheetId';
  }

  String _accountKey() {
    final user = authService.currentUser;
    final rawKey = user?.id.trim().isNotEmpty == true
        ? user!.id
        : user?.email.trim().isNotEmpty == true
        ? user!.email
        : 'default';
    return Uri.encodeComponent(rawKey);
  }
}

class GoogleSheetsSyncResult {
  const GoogleSheetsSyncResult({
    required this.totalCount,
    required this.syncedCount,
    required this.skippedCount,
    this.isEnabled = true,
  });

  const GoogleSheetsSyncResult.disabled()
    : totalCount = 0,
      syncedCount = 0,
      skippedCount = 0,
      isEnabled = false;

  const GoogleSheetsSyncResult.empty()
    : totalCount = 0,
      syncedCount = 0,
      skippedCount = 0,
      isEnabled = true;

  final int totalCount;
  final int syncedCount;
  final int skippedCount;
  final bool isEnabled;
}
