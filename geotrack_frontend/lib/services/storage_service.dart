import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geotrack_frontend/models/gps_data_model.dart';
import 'dart:convert';

class StorageService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final String _tokenKey = 'auth_token';
  final String _pendingDataKey = 'pending_gps_data';
  final String _syncedDataKey = 'synced_gps_data';
  final String _customApiUrlKey = 'custom_api_url';
  final String _lastSyncKey = 'last_sync_time';

  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  Future<String?> getToken() async {
    return await _secureStorage.read(key: _tokenKey);
  }

  Future<void> deleteToken() async {
    await _secureStorage.delete(key: _tokenKey);
  }

  Future<void> savePendingGpsData(GpsData data) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingData = await getPendingGpsData();

    // Éviter les doublons basés sur le timestamp et la position
    final isDuplicate = pendingData.any(
      (existing) =>
          existing.idname == data.idname &&
          existing.datetime.isAtSameMomentAs(data.datetime) &&
          existing.latitude == data.latitude &&
          existing.longitude == data.longitude,
    );

    if (!isDuplicate) {
      pendingData.add(data.copyWith(synced: false));

      final jsonList = pendingData.map((e) => e.toJson()).toList();
      await prefs.setString(_pendingDataKey, json.encode(jsonList));
      print('💾 Saved pending GPS data: ${data.idname} at ${data.datetime}');
    }
  }

  Future<List<GpsData>> getPendingGpsData() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_pendingDataKey);

    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((json) => GpsData.fromJson(json)).toList();
    } catch (e) {
      print('❌ Error decoding pending GPS data: $e');
      return [];
    }
  }

  Future<void> removePendingGpsData(GpsData data) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingData = await getPendingGpsData();

    final updatedData =
        pendingData
            .where(
              (existing) =>
                  !(existing.idname == data.idname &&
                      existing.datetime.isAtSameMomentAs(data.datetime) &&
                      existing.latitude == data.latitude &&
                      existing.longitude == data.longitude),
            )
            .toList();

    final jsonList = updatedData.map((e) => e.toJson()).toList();
    await prefs.setString(_pendingDataKey, json.encode(jsonList));
  }

  Future<void> removePendingGpsDataById(GpsData data) async {
    await removePendingGpsData(data);
  }

  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingDataKey);
    await prefs.remove(_syncedDataKey);
    await deleteToken();
    print('🗑️ All data cleared');
  }

  Future<List<GpsData>> getAllGpsData() async {
    final pendingData = await getPendingGpsData();
    final syncedData = await getSyncedGpsData();

    final allData = [...pendingData, ...syncedData];
    allData.sort((a, b) => b.datetime.compareTo(a.datetime));

    return allData;
  }

  Future<void> saveSyncedGpsData(GpsData data) async {
    final prefs = await SharedPreferences.getInstance();
    final syncedData = await getSyncedGpsData();

    // Vérifier si la donnée existe déjà
    final existingIndex = syncedData.indexWhere((d) => d.id == data.id);
    if (existingIndex != -1) {
      syncedData[existingIndex] = data.copyWith(synced: true);
    } else {
      syncedData.add(data.copyWith(synced: true));
    }

    final jsonList = syncedData.map((e) => e.toJson()).toList();
    await prefs.setString(_syncedDataKey, json.encode(jsonList));

    // Sauvegarder le timestamp de la dernière sync
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());

    print('💾 Saved synced GPS data: ${data.idname} (ID: ${data.id})');
  }

  Future<List<GpsData>> getSyncedGpsData() async {
    final prefs = await SharedPreferences.getInstance();
    final syncedJsonString = prefs.getString(_syncedDataKey);

    if (syncedJsonString == null || syncedJsonString.isEmpty) {
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

  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncString = prefs.getString(_lastSyncKey);

    if (lastSyncString != null) {
      return DateTime.parse(lastSyncString);
    }
    return null;
  }

  Future<void> saveCustomUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    // Nettoyer l'URL
    String cleanedUrl = url.trim();
    if (!cleanedUrl.endsWith('/')) {
      cleanedUrl = '$cleanedUrl/';
    }
    await prefs.setString(_customApiUrlKey, cleanedUrl);
    print('🌐 Saved custom API URL: $cleanedUrl');
  }

  Future<String?> getCustomUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_customApiUrlKey);
  }

  Future<void> clearCustomUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customApiUrlKey);
    print('🌐 Cleared custom API URL');
  }

  Future<void> clearPendingData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingDataKey);
    print('🗑️ Cleared pending data');
  }

  Future<void> clearSyncedData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_syncedDataKey);
    print('🗑️ Cleared synced data');
  }
}
