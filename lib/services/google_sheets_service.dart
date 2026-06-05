import 'dart:convert';

import 'package:_discoveryapis_commons/_discoveryapis_commons.dart' as commons;
import 'package:googleapis/drive/v3.dart' as drive;
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
  static const String _syncedDetailIdsPrefix =
      'googleSheetsTableSyncedDetailIds';
  static const String _spreadsheetMarkerKey = 'digitalWalletData';
  static const String _spreadsheetMarkerValue = 'primary';
  static const String _combinedCategoryHeader = 'Category';
  static const List<String> _keyValueHeaders = <String>['Key', 'Value'];
  static const List<String> _legacyHeaders = <String>[
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
  final Map<String, Set<String>> _knownSheets = <String, Set<String>>{};
  final Map<String, List<String>> _headersBySheet = <String, List<String>>{};
  String? _cachedSpreadsheetId;
  String? _cachedSpreadsheetAccountKey;

  Future<GoogleSheetsSyncResult> syncSavedSecureDetails() async {
    return _syncSavedSecureDetails(allowAuthorizationRetry: true);
  }

  Future<GoogleSheetsSyncResult> _syncSavedSecureDetails({
    required bool allowAuthorizationRetry,
  }) async {
    if (!config.enabled) return const GoogleSheetsSyncResult.disabled();

    if (!authService.isSignedIn) {
      await authService.signIn();
    }

    final details = await recentFileStore.listSecureDetails();
    if (details.isEmpty) return const GoogleSheetsSyncResult.empty();

    final client = await authService.authClient();
    try {
      final api = sheets.SheetsApi(client);
      final spreadsheetId = await _spreadsheetId(
        api,
        drive.DriveApi(client),
        initialSheetName: worksheetNameFor(details.first),
      );

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
      if (allowAuthorizationRetry && AuthService.isInsufficientScope(error)) {
        await authService.reauthorize();
        return _syncSavedSecureDetails(allowAuthorizationRetry: false);
      }
      throw StateError(_sheetsSetupMessage(error));
    } on commons.ApiRequestError catch (error) {
      if (allowAuthorizationRetry && AuthService.isInsufficientScope(error)) {
        await authService.reauthorize();
        return _syncSavedSecureDetails(allowAuthorizationRetry: false);
      }
      throw StateError(
        AuthService.friendlyGoogleError(error, service: 'Google Sheets'),
      );
    } finally {
      client.close();
    }
  }

  Future<void> appendSecureDetail(SecureDetail detail) async {
    return _appendSecureDetail(detail, allowAuthorizationRetry: true);
  }

  Future<void> _appendSecureDetail(
    SecureDetail detail, {
    required bool allowAuthorizationRetry,
  }) async {
    if (!config.enabled) return;

    if (!authService.isSignedIn) {
      await authService.signIn();
    }

    final client = await authService.authClient();
    try {
      final api = sheets.SheetsApi(client);
      final sheetName = worksheetNameFor(detail);
      final spreadsheetId = await _spreadsheetId(
        api,
        drive.DriveApi(client),
        initialSheetName: sheetName,
      );

      final syncedIds = await _syncedDetailIds(spreadsheetId);
      if (syncedIds.contains(detail.id)) return;

      await _appendRow(api, spreadsheetId, detail);
      syncedIds.add(detail.id);
      await _saveSyncedDetailIds(spreadsheetId, syncedIds);
    } on commons.DetailedApiRequestError catch (error) {
      if (allowAuthorizationRetry && AuthService.isInsufficientScope(error)) {
        await authService.reauthorize();
        return _appendSecureDetail(detail, allowAuthorizationRetry: false);
      }
      throw StateError(_sheetsSetupMessage(error));
    } on commons.ApiRequestError catch (error) {
      if (allowAuthorizationRetry && AuthService.isInsufficientScope(error)) {
        await authService.reauthorize();
        return _appendSecureDetail(detail, allowAuthorizationRetry: false);
      }
      throw StateError(
        AuthService.friendlyGoogleError(error, service: 'Google Sheets'),
      );
    } finally {
      client.close();
    }
  }

  Future<String> _spreadsheetId(
    sheets.SheetsApi api,
    drive.DriveApi driveApi, {
    required String initialSheetName,
  }) async {
    final accountKey = _accountKey();
    if (_cachedSpreadsheetAccountKey == accountKey &&
        _cachedSpreadsheetId != null) {
      return _cachedSpreadsheetId!;
    }

    final configuredId = _cleanSpreadsheetId(config.spreadsheetId);
    if (configuredId.isNotEmpty) {
      _cacheSpreadsheetId(accountKey, configuredId);
      return configuredId;
    }

    final storedId = await recentFileStore.getSetting(_storedSpreadsheetIdKey);
    if (storedId != null && storedId.trim().isNotEmpty) {
      _cacheSpreadsheetId(accountKey, storedId);
      return storedId;
    }

    final existingId = await _findExistingSpreadsheetId(driveApi);
    if (existingId != null) {
      await recentFileStore.setSetting(_storedSpreadsheetIdKey, existingId);
      _cacheSpreadsheetId(accountKey, existingId);
      await _markSpreadsheet(driveApi, existingId);
      return existingId;
    }

    final spreadsheet = await api.spreadsheets.create(
      sheets.Spreadsheet(
        properties: sheets.SpreadsheetProperties(
          title: config.spreadsheetTitle,
        ),
        sheets: <sheets.Sheet>[
          sheets.Sheet(
            properties: sheets.SheetProperties(title: initialSheetName),
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
    _cacheSpreadsheetId(accountKey, createdId);
    _knownSheets[createdId] = <String>{initialSheetName};
    await _markSpreadsheet(driveApi, createdId);
    return createdId;
  }

  Future<String?> _findExistingSpreadsheetId(drive.DriveApi api) async {
    final baseQuery = <String>[
      'trashed = false',
      "mimeType = 'application/vnd.google-apps.spreadsheet'",
    ];
    final queries = <String>[
      <String>[
        ...baseQuery,
        "appProperties has { key='$_spreadsheetMarkerKey' and value='$_spreadsheetMarkerValue' }",
      ].join(' and '),
      <String>[
        ...baseQuery,
        'name = ${_driveQueryLiteral(config.spreadsheetTitle)}',
      ].join(' and '),
    ];

    for (final query in queries) {
      final response = await api.files.list(
        q: query,
        orderBy: 'modifiedTime desc',
        pageSize: 1,
        spaces: 'drive',
        $fields: 'files(id)',
      );
      final id = response.files
          ?.map((file) => file.id)
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .firstOrNull;
      if (id != null) return id;
    }
    return null;
  }

  Future<void> _markSpreadsheet(
    drive.DriveApi api,
    String spreadsheetId,
  ) async {
    try {
      await api.files.update(
        drive.File()
          ..appProperties = const <String, String>{
            _spreadsheetMarkerKey: _spreadsheetMarkerValue,
          },
        spreadsheetId,
        $fields: 'id',
      );
    } catch (_) {
      // The exact title lookup still prevents duplicate spreadsheet creation.
    }
  }

  Future<void> _appendRow(
    sheets.SheetsApi api,
    String spreadsheetId,
    SecureDetail detail,
  ) async {
    final sheetName = worksheetNameFor(detail);
    await _ensureSheetExists(api, spreadsheetId, sheetName);
    final headers = await _ensureHeadersForDetail(
      api,
      spreadsheetId,
      sheetName,
      detail,
    );
    await api.spreadsheets.values.append(
      sheets.ValueRange(values: <List<Object?>>[rowForDetail(detail, headers)]),
      spreadsheetId,
      _range(sheetName, 'A1'),
      insertDataOption: 'INSERT_ROWS',
      valueInputOption: 'USER_ENTERED',
    );
  }

  Future<void> _ensureSheetExists(
    sheets.SheetsApi api,
    String spreadsheetId,
    String sheetName,
  ) async {
    final known = _knownSheets[spreadsheetId];
    if (known?.contains(sheetName) == true) return;

    final spreadsheet = await api.spreadsheets.get(
      spreadsheetId,
      $fields: 'sheets.properties.title',
    );
    final sheetNames =
        spreadsheet.sheets
            ?.map((sheet) => sheet.properties?.title)
            .whereType<String>()
            .toSet() ??
        <String>{};
    _knownSheets[spreadsheetId] = sheetNames;
    final exists = sheetNames.contains(sheetName);
    if (exists) return;

    await api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(
        requests: <sheets.Request>[
          sheets.Request(
            addSheet: sheets.AddSheetRequest(
              properties: sheets.SheetProperties(title: sheetName),
            ),
          ),
        ],
      ),
      spreadsheetId,
    );
    sheetNames.add(sheetName);
  }

  Future<List<String>> _ensureHeadersForDetail(
    sheets.SheetsApi api,
    String spreadsheetId,
    String sheetName,
    SecureDetail detail,
  ) async {
    final cacheKey = _sheetCacheKey(spreadsheetId, sheetName);
    var headers = List<String>.of(
      _headersBySheet[cacheKey] ??
          await _readHeaderRow(api, spreadsheetId, sheetName),
    );

    if (_rowStartsWith(headers, _legacyHeaders) ||
        _rowStartsWith(headers, _keyValueHeaders) ||
        headers.firstOrNull == _combinedCategoryHeader) {
      await api.spreadsheets.values.clear(
        sheets.ClearValuesRequest(),
        spreadsheetId,
        _range(sheetName, 'A:ZZ'),
      );
      headers = <String>[];
    }

    var shouldWriteHeaders = headers.isEmpty;

    for (final entry in detail.fields.entries) {
      final label = SecureDetail.labelFor(entry.key);
      if (headers.contains(label)) continue;
      headers.add(label);
      shouldWriteHeaders = true;
    }

    if (shouldWriteHeaders) {
      await _writeHeaderRow(api, spreadsheetId, sheetName, headers);
    }

    _headersBySheet[cacheKey] = List<String>.unmodifiable(headers);
    return headers;
  }

  Future<List<String>> _readHeaderRow(
    sheets.SheetsApi api,
    String spreadsheetId,
    String sheetName,
  ) async {
    final existing = await api.spreadsheets.values.get(
      spreadsheetId,
      _range(sheetName, 'A1:ZZ1'),
    );
    final firstRow = existing.values?.firstOrNull ?? const <Object?>[];
    return firstRow
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Future<void> _writeHeaderRow(
    sheets.SheetsApi api,
    String spreadsheetId,
    String sheetName,
    List<String> headers,
  ) {
    return api.spreadsheets.values.update(
      sheets.ValueRange(values: <List<Object?>>[headers]),
      spreadsheetId,
      _range(sheetName, 'A1:${_columnName(headers.length)}1'),
      valueInputOption: 'RAW',
    );
  }

  static List<Object?> rowForDetail(SecureDetail detail, List<String> headers) {
    final row = List<Object?>.filled(headers.length, '');

    for (final entry in detail.fields.entries) {
      final columnIndex = headers.indexOf(SecureDetail.labelFor(entry.key));
      if (columnIndex == -1) continue;
      row[columnIndex] = entry.value;
    }

    return row;
  }

  static String worksheetNameFor(SecureDetail detail) {
    final sanitized = detail.categoryName
        .replaceAll(RegExp(r"[\[\]:*?/\\]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (sanitized.isEmpty) return 'Secure Detail';
    return sanitized.length <= 100 ? sanitized : sanitized.substring(0, 100);
  }

  bool _rowStartsWith(List<Object?> row, List<String> expected) {
    if (row.length < expected.length) return false;
    for (var index = 0; index < expected.length; index++) {
      if (row[index].toString().trim() != expected[index]) return false;
    }
    return true;
  }

  String _range(String sheetName, String cellRange) {
    final escapedSheetName = sheetName.replaceAll("'", "''");
    return "'$escapedSheetName'!$cellRange";
  }

  String _columnName(int index) {
    var number = index;
    var name = '';
    while (number > 0) {
      number--;
      name = String.fromCharCode(65 + (number % 26)) + name;
      number ~/= 26;
    }
    return name;
  }

  void _cacheSpreadsheetId(String accountKey, String spreadsheetId) {
    if (_cachedSpreadsheetAccountKey != accountKey) {
      _knownSheets.clear();
      _headersBySheet.clear();
    }
    _cachedSpreadsheetAccountKey = accountKey;
    _cachedSpreadsheetId = spreadsheetId;
  }

  String _sheetCacheKey(String spreadsheetId, String sheetName) {
    return '$spreadsheetId::$sheetName';
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

  String _driveQueryLiteral(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    return "'$escaped'";
  }

  String _sheetsSetupMessage(commons.DetailedApiRequestError error) {
    final message = error.message ?? '';
    if (AuthService.isInsufficientScope(error)) {
      return 'Google permission is missing. Reconnect Google and approve Drive access.';
    }
    if (error.status == 403 &&
        message.contains('Google Sheets API has not been used')) {
      return 'Google Sheets API is disabled in the OAuth project. Enable it in Google Cloud Console, wait a few minutes, and try again.';
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
