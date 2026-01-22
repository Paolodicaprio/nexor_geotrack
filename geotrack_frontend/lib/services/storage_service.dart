import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geotrack_frontend/utils/db_name_extractor.dart';
import 'package:hive/hive.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geotrack_frontend/models/gps_data_model.dart';
import 'dart:convert';
import 'package:nanoid/nanoid.dart';

import '../models/config_model.dart';
import '../utils/constants.dart';
import 'isar_service.dart';

class StorageService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final String _cookieKey = 'auth_token';
  final String _pendingDataKey = 'pending_gps_data';
  final String _syncedDataKey = 'synced_gps_data';
  final String _customApiUrlKey = 'custom_api_url';
  final String _deviceIdKey = 'device_id';
  final String _databaseNameKey = 'database_name';
  final String _configKey = 'config';

  void reloadStorage() async{
     SharedPreferences prefs = await SharedPreferences.getInstance();
     await prefs.reload();
  }
  Future<void> saveToken(String token) async {
    print('💾 Saving token: ${token}...');
    await _secureStorage.write(key: _cookieKey, value: token);
  }

  Future<String?> getToken() async {
    final token = await _secureStorage.read(key: _cookieKey);
    print('💾 Retrieved token: ${token != null ? "exists" : "null"}');
    return token;
  }

  Future<void> deleteToken() async {
    await _secureStorage.delete(key: _cookieKey);
  }

  Future<void> savePendingGpsData(GpsData data) async {
    try {
      final isarDb = await IsarService().db;

      await isarDb.writeTxn(() async {
        await isarDb.gpsDatas.put(data);
      });

      // Nettoyage des anciennes données non synchronisées
      await cleanOldPendingData();
    } catch (e) {
      print("Error saving data : $e");
    }
  }

  // recuperer les données non synchronisées
  Future<List<GpsData>> getPendingGpsData() async {
    try {
      final isarDb = await IsarService().db;

      return await isarDb.gpsDatas
          .filter()
          .syncedEqualTo(false)
          .sortByTimestamp()
          .findAll();

    } catch (e) {
      print("Error retrieving data : $e");
      return [];
    }
  }


  /// Marque une liste de données comme synchronisés.
  Future<void> markAllAsSynced(List<GpsData> dataToSync) async {
    final isar = await IsarService().db;
    final updatedData = dataToSync
        .map((data) => data.copyWith(synced: true))
        .toList();
    await isar.writeTxn(() async {
      await isar.gpsDatas.putAll(updatedData);
    });
    await cleanOldSyncedData();
  }

  Future<void> removePendingGpsData(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingData = await getPendingGpsData();

    final updatedData = pendingData.where((data) => data.id != id).toList();

    final jsonList = updatedData.map((e) => e.toJson()).toList();
    await prefs.setString(_pendingDataKey, json.encode(jsonList));
  }

  Future<void> clearAllData() async {
    final isar = await IsarService().db;
    await isar.writeTxn(() async {
      await isar.gpsDatas.clear();
    });
    await deleteToken();
  }

  /// Retourne toutes les données GPS (en attente et synchronisées)
  Future<List<GpsData>> getAllGpsData() async {
    try {
      final isarDb = await IsarService().db;

      // triées par 'timestamp' de manière décroissante (du plus récent au plus ancien).
      return await isarDb.gpsDatas
          .where()
          .sortByTimestampDesc()
          .findAll();

    } catch (e) {
      print("❌ Error retrieving all GPS data: $e");
      return [];
    }
  }

  Future<void> saveSyncedGpsData(GpsData data) async {
    try {
      final isarDb = await IsarService().db;

      await isarDb.writeTxn(() async {
        final syncedData = data.copyWith(synced: true);

        await isarDb.gpsDatas.put(syncedData);
      });

    } catch (e) {
      print("❌ Error saving synced data: $e");
    }
  }

  // Récupérer UNIQUEMENT les données synchronisées
  Future<List<GpsData>> getSyncedGpsData() async {
    try {
      final isarDb = await IsarService().db;

      return await isarDb.gpsDatas
          .filter()
          .syncedEqualTo(true)
          .sortByTimestampDesc() // Tri du plus récent au plus ancien pour l'historique
          .findAll();

    } catch (e) {
      print("❌ Error retrieving synced data: $e");
      return [];
    }
  }

  /// Supprime les données synchronisées les plus anciennes pour n'en garder que les X derniers.
  Future<void> cleanOldSyncedData() async {
    final isar = await IsarService().db;

    final totalSynced = await isar.gpsDatas.filter().syncedEqualTo(true).count();

    if (totalSynced > Constants.syncedLimit) {
      final itemsToDelete = totalSynced - Constants.syncedLimit;

      await isar.writeTxn(() async {
        //  Trouver les IDs des "itemsToDelete" les plus anciens (tri croissant)
        final idsToDelete = await isar.gpsDatas
            .filter()
            .syncedEqualTo(true)
            .sortByTimestamp() // Tri du plus ancien au plus récent
            .limit(itemsToDelete)
            .findAll();

        await isar.gpsDatas.deleteAll(idsToDelete.map((data) => data.id).toList());
        print('🗑️ Nettoyage des synchronisés : $itemsToDelete enregistrements supprimés.');
      });
    }
  }

  /// Supprime les données non synchronisées les plus anciennes pour n'en garder que Y.
  Future<void> cleanOldPendingData() async {
    final isar = await IsarService().db;

    final totalPending = await isar.gpsDatas.filter().syncedEqualTo(false).count();

    if (totalPending > Constants.pendingLimit) {
      final itemsToDelete = totalPending - Constants.pendingLimit;

      await isar.writeTxn(() async {
        // Trouver les IDs des "itemsToDelete" les plus anciens (tri croissant)
        final idsToDelete = await isar.gpsDatas
            .filter()
            .syncedEqualTo(false)
            .sortByTimestamp() // Tri du plus ancien au plus récent
            .limit(itemsToDelete)
            .findAll();
        await isar.gpsDatas.deleteAll(idsToDelete.map((data) => data.id).toList());
        print('🗑️ Nettoyage des Pending : $itemsToDelete enregistrements supprimés.');
      });
    }
  }

  /// Sauvegarde l'URL entrée par l'utilisateur
  Future<void> saveCustomUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customApiUrlKey, url);
  }

  // verifier que l'utilisateur a deja une url personnalisé
  Future<bool> hasCustomUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_customApiUrlKey);
    return value != null && value.isNotEmpty;
  }

  /// Récupère l'URL personnalisée si elle existe
  Future<String> getCustomUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_customApiUrlKey);
    if (value==null || value.isEmpty){
      return dotenv.get('API_BASE_URL', fallback: Constants.apiBaseUrl);
    }
    return value;
  }

  /// Supprime l'URL personnalisée (revenir aux valeurs par défaut)
  Future<void> clearCustomUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customApiUrlKey);
  }

  /// Sauvegarde la DB name entrée par l'utilisateur
  Future<void> saveDatabaseName(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_databaseNameKey, url);
  }

  /// Récupère la DB name si elle existe
  Future<String> getDatabaseName() async {
    final prefs = await SharedPreferences.getInstance();
    final value =  prefs.getString(_databaseNameKey);
    if (value ==null || value.isEmpty){
      final newValue =  extractDatabaseName(await getCustomUrl());
      return newValue ?? dotenv.get('DATABASE_NAME', fallback: 'database_name');
    }
    return value;
  }

  /// Supprime la DB name (revenir aux valeurs par défaut)
  Future<void> clearDatabaseName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_databaseNameKey);
  }

  Future<void> saveUserUsername(String username) async {
    await _secureStorage.write(key: 'user_username', value: username);
  }

  Future<String?> getUserUsername() async {
    return await _secureStorage.read(key: 'user_username');
  }

  Future<void> deleteUserUsername() async {
    await _secureStorage.delete(key: 'user_username');
  }

  Future<void> savePassword(String password) async {
    await _secureStorage.write(key: 'password', value: password);
  }

  Future<String?> getPassword() async {
    return await _secureStorage.read(key: 'password');
  }

  Future<void> deletePassword() async {
    await _secureStorage.delete(key: 'password');
  }

  Future<void> saveTimerStates({
    DateTime? nextGpsTime,
    DateTime? nextSyncTime,
    DateTime? nextConfigTime,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (nextGpsTime != null) {
      await prefs.setString('next_gps_time', nextGpsTime.toIso8601String());
    } else {
      await prefs.remove('next_gps_time');
    }
    
    if (nextSyncTime != null) {
      await prefs.setString('next_sync_time', nextSyncTime.toIso8601String());
    } else {
      await prefs.remove('next_sync_time');
    }
    
    if (nextConfigTime != null) {
      await prefs.setString('next_config_time', nextConfigTime.toIso8601String());
    } else {
      await prefs.remove('next_config_time');
    }
  }

  Future<Map<String, DateTime?>> getTimerStates() async {
    final prefs = await SharedPreferences.getInstance();
    
    DateTime? parseDateTime(String? value) {
      if (value == null || value.isEmpty) return null;
      try {
        return DateTime.parse(value);
      } catch (e) {
        return null;
      }
    }
    
    return {
      'gps': parseDateTime(prefs.getString('next_gps_time')),
      'sync': parseDateTime(prefs.getString('next_sync_time')),
      'config': parseDateTime(prefs.getString('next_config_time')),
    };
  }

  Future<String?> getDeviceCode() async {
    return await _secureStorage.read(key: _deviceIdKey);
  }

  Future<void> saveDeviceId(String deviceId) async {
    await _secureStorage.write(key: _deviceIdKey, value: deviceId);
  }

  Future<void> deleteDeviceId() async {
    await _secureStorage.delete(key: _deviceIdKey);
  }

  Future<void> saveConfig(Config config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, json.encode(config.toJson()));
  }

  Future<Config> getConfig()  async{
    final prefs = await SharedPreferences.getInstance();
    final jsonConfig = prefs.getString(_configKey);
    if (jsonConfig ==null){
      return Config.fromDefault();
    }
    try {
      final config = Config.fromJson(json.decode(jsonConfig));
      return config;
    } catch (e) {
     throw Exception('Error while decoding config: $e');
    }
  }

  Future<DateTime?> getLastCollectionTime() async{
    final prefs = await SharedPreferences.getInstance();
    final String? last_collect = await prefs.getString("last_collection");
    return last_collect !=null ? DateTime.parse(last_collect) : null;
  }

  Future<void> setLastCollectionTime(DateTime last_collect) async{
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("last_collection",last_collect.toIso8601String());
  }
}
