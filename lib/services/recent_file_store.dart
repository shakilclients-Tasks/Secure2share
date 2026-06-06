import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/recent_file.dart';
import '../models/secure_detail.dart';

class RecentFileStore {
  Database? _database;
  final List<SecureDetail> _sessionSecureDetails = <SecureDetail>[];

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    _database = await openDatabase(
      p.join(dbPath, 'drive2share_flutter.db'),
      version: 4,
      onCreate: (db, version) async {
        await _createRecentFilesTable(db);
        await _createSettingsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createSettingsTable(db);
        }
        if (oldVersion < 4) {
          await db.execute('DROP TABLE IF EXISTS secure_details');
        }
      },
    );
  }

  Future<void> _createRecentFilesTable(Database db) async {
    await db.execute('''
          CREATE TABLE recent_files(
            id TEXT PRIMARY KEY,
            driveFileId TEXT,
            name TEXT NOT NULL,
            mimeType TEXT NOT NULL,
            localPath TEXT NOT NULL,
            sizeBytes INTEGER NOT NULL,
            modifiedAtMillis INTEGER NOT NULL,
            importedAtMillis INTEGER NOT NULL
          )
        ''');
  }

  Future<void> _createSettingsTable(Database db) async {
    await db.execute('''
          CREATE TABLE IF NOT EXISTS app_settings(
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
  }

  Future<void> save(RecentFile file) async {
    await _db.insert(
      'recent_files',
      file.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<RecentFile>> list({int? limit}) async {
    final rows = await _db.query(
      'recent_files',
      orderBy: 'importedAtMillis DESC',
      limit: limit,
    );
    return rows.map(RecentFile.fromMap).toList();
  }

  Future<RecentFile?> getById(String id) async {
    final rows = await _db.query(
      'recent_files',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return RecentFile.fromMap(rows.first);
  }

  Future<void> delete(String id) async {
    await _db.delete('recent_files', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> saveSecureDetail(SecureDetail detail) async {
    _sessionSecureDetails.removeWhere((item) => item.id == detail.id);
    _sessionSecureDetails.insert(0, detail);
  }

  Future<List<SecureDetail>> listSecureDetails({int? limit}) async {
    final details = List<SecureDetail>.unmodifiable(_sessionSecureDetails);
    if (limit == null || details.length <= limit) return details;
    return details.take(limit).toList(growable: false);
  }

  Future<void> deleteSecureDetail(String id) async {
    _sessionSecureDetails.removeWhere((detail) => detail.id == id);
  }

  Future<String?> getSetting(String key) async {
    final rows = await _db.query(
      'app_settings',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await _db.insert('app_settings', <String, Object?>{
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Database get _db {
    final database = _database;
    if (database == null) {
      throw StateError('RecentFileStore.init() must be called first.');
    }
    return database;
  }
}
