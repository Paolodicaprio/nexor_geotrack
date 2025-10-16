import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geotrack_frontend/utils/db_name_extractor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geotrack_frontend/models/gps_data_model.dart';
import 'dart:convert';
import 'package:nanoid/nanoid.dart';

import '../models/config_model.dart';
import '../utils/constants.dart';

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
    final prefs = await SharedPreferences.getInstance();
    final pendingData = await getPendingGpsData();

    pendingData.add(data);

    final jsonList = pendingData.map((e) => e.toJson()).toList();
    await prefs.setString(_pendingDataKey, json.encode(jsonList));
  }

  Future<List<GpsData>> getPendingGpsData() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_pendingDataKey);

    if (jsonString == null) {
      return [];
    }

    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((json) => GpsData.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> removePendingGpsData(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingData = await getPendingGpsData();

    final updatedData = pendingData.where((data) => data.id != id).toList();

    final jsonList = updatedData.map((e) => e.toJson()).toList();
    await prefs.setString(_pendingDataKey, json.encode(jsonList));
  }

  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingDataKey);
    await prefs.remove(_syncedDataKey);
    await deleteToken();
  }

  /// Retourne toutes les données GPS (en attente et synchronisées)
  Future<List<GpsData>> getAllGpsData() async {
    final pendingData = await getPendingGpsData();
    final syncedData = await getSyncedGpsData();

    // Combiner et trier par timestamp décroissant
    final allData = [...pendingData, ...syncedData];
    allData.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return allData;
  }

  Future<void> saveSyncedGpsData(GpsData data) async {
    final prefs = await SharedPreferences.getInstance();
    final syncedData = await getSyncedGpsData();

    // Vérifier si la donnée existe déjà pour éviter les doublons
    final existingIndex = syncedData.indexWhere((d) => d.id == data.id);
    if (existingIndex != -1) {
      // Mettre à jour la donnée existante
      syncedData[existingIndex] = data.copyWith(synced: true);
    } else {
      // Ajouter la nouvelle donnée synchronisée
      syncedData.add(data.copyWith(synced: true));
    }

    final jsonList =
        syncedData
            .map(
              (e) => {
                ...e.toJson(),
                'synced': true, // S'assurer que synced est bien sauvegardé
                'id': e.id, // S'assurer que l'ID est sauvegardé
              },
            )
            .toList();

    await prefs.setString(_syncedDataKey, json.encode(jsonList));
  }

  // Ajouter cette méthode pour récupérer uniquement les données synchronisées
  Future<List<GpsData>> getSyncedGpsData() async {
    final prefs = await SharedPreferences.getInstance();
    final syncedJsonString = prefs.getString(_syncedDataKey);

    if (syncedJsonString == null) {
      return [];
    }

    try {
      final List<dynamic> syncedJsonList = json.decode(syncedJsonString);
      return syncedJsonList.map((json) => GpsData.fromJson(json)).toList();
    } catch (e) {
      print('❌ Error decoding synced data: $e');
      return [];
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
    // await prefs.setInt("collect_interval", config.collectionInterval);
    // await prefs.setInt("sync_interval", config.sendInterval);
    // await prefs.setInt("config_sync_interval",config.configSyncInterval);
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
