import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:geotrack_frontend/models/gps_data_model.dart';

class DatabaseService {
  static Database? _database;
  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = await getDatabasesPath();
    final databasePath = join(path, 'geotrack.db');

    return await openDatabase(
      databasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE gps_data(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            idname TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            datetime TEXT NOT NULL,
            created_at TEXT,
            synced INTEGER DEFAULT 0,
            api_id INTEGER
          )
        ''');

        await db.execute('CREATE INDEX idx_gps_synced ON gps_data(synced)');
        await db.execute('CREATE INDEX idx_gps_datetime ON gps_data(datetime)');
        await db.execute('CREATE INDEX idx_gps_idname ON gps_data(idname)');

        print('✅ Database créée avec index');
      },
    );
  }

  Future<int> saveGpsData(
    GpsData data, {
    bool synced = false,
    int? apiId,
  }) async {
    final db = await database;

    final id = await db.insert('gps_data', {
      'idname': data.idname,
      'latitude': data.latitude,
      'longitude': data.longitude,
      'datetime': data.datetime.toIso8601String(),
      'created_at':
          data.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'synced': synced ? 1 : 0,
      'api_id': apiId,
    });

    print('💾 Donnée GPS sauvegardée: ${data.idname} (sync: $synced, ID: $id)');
    return id;
  }

  Future<List<GpsData>> getPendingGpsData() async {
    final db = await database;

    final results = await db.query(
      'gps_data',
      where: 'synced = 0',
      orderBy: 'datetime DESC',
    );

    return results.map(_mapToGpsData).toList();
  }

  Future<List<GpsData>> getSyncedGpsData() async {
    final db = await database;

    final results = await db.query(
      'gps_data',
      where: 'synced = 1',
      orderBy: 'datetime DESC',
    );

    return results.map(_mapToGpsData).toList();
  }

  Future<List<GpsData>> getAllGpsData() async {
    final db = await database;

    final results = await db.query('gps_data', orderBy: 'datetime DESC');

    return results.map(_mapToGpsData).toList();
  }

  Future<int> getPendingCount() async {
    final db = await database;

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM gps_data WHERE synced = 0',
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getSyncedCount() async {
    final db = await database;

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM gps_data WHERE synced = 1',
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> markAsSynced(int localId, int apiId) async {
    final db = await database;

    await db.update(
      'gps_data',
      {'synced': 1, 'api_id': apiId},
      where: 'id = ?',
      whereArgs: [localId],
    );

    print('✅ Marqué comme synchronisé: ID local $localId → ID API $apiId');
  }

  Future<void> markMultipleAsSynced(
    List<Map<String, dynamic>> syncedData,
  ) async {
    final db = await database;

    final batch = db.batch();

    for (var item in syncedData) {
      final localId = item['local_id'];
      final apiId = item['api_id'];

      if (localId != null && apiId != null) {
        batch.update(
          'gps_data',
          {'synced': 1, 'api_id': apiId},
          where: 'id = ?',
          whereArgs: [localId],
        );
      }
    }

    await batch.commit(noResult: true);
    print('✅ ${syncedData.length} données marquées comme synchronisées');
  }

  Future<void> deleteGpsData(int id) async {
    final db = await database;

    await db.delete('gps_data', where: 'id = ?', whereArgs: [id]);

    print('🗑️ Donnée GPS supprimée: ID $id');
  }

  Future<void> clearAllData() async {
    final db = await database;

    await db.delete('gps_data');
    print('🗑️ Toutes les données GPS supprimées');
  }

  Future<int> clearSyncedData() async {
    final db = await database;

    final count = await db.delete('gps_data', where: 'synced = 1');

    print('🗑️ $count données synchronisées supprimées');
    return count;
  }

  Future<int> clearPendingData() async {
    final db = await database;

    final count = await db.delete('gps_data', where: 'synced = 0');

    print('🗑️ $count données en attente supprimées');
    return count;
  }

  Future<DateTime?> getLastCollectionTime() async {
    final db = await database;

    final result = await db.rawQuery(
      'SELECT datetime FROM gps_data ORDER BY datetime DESC LIMIT 1',
    );

    if (result.isEmpty) return null;

    final dateString = result.first['datetime'] as String?;
    return dateString != null ? DateTime.parse(dateString) : null;
  }

  Future<DateTime?> getLastSyncTime() async {
    final db = await database;

    final result = await db.rawQuery(
      'SELECT datetime FROM gps_data WHERE synced = 1 ORDER BY datetime DESC LIMIT 1',
    );

    if (result.isEmpty) return null;

    final dateString = result.first['datetime'] as String?;
    return dateString != null ? DateTime.parse(dateString) : null;
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      print('🔒 Base de données fermée');
    }
  }

  GpsData _mapToGpsData(Map<String, dynamic> map) {
    return GpsData(
      id: map['api_id'] ?? map['id'],
      idname: map['idname'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      datetime: DateTime.parse(map['datetime'] as String),
      createdAt:
          map['created_at'] != null
              ? DateTime.parse(map['created_at'] as String)
              : null,
      synced: (map['synced'] as int) == 1,
    );
  }
}
