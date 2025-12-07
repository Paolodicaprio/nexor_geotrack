import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final String _tokenKey = 'auth_token';
  final String _customApiUrlKey = 'custom_api_url';
  final String _lastSyncKey = 'last_sync_time';
  final String _userEmailKey = 'user_email';

  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  Future<String?> getToken() async {
    return await _secureStorage.read(key: _tokenKey);
  }

  Future<void> deleteToken() async {
    await _secureStorage.delete(key: _tokenKey);
  }

  Future<void> saveUserEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userEmailKey, email);
  }

  Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userEmailKey);
  }

  Future<void> deleteUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userEmailKey);
  }

  Future<void> saveCustomUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    String cleanedUrl = url.trim();
    if (!cleanedUrl.endsWith('/')) {
      cleanedUrl = '$cleanedUrl/';
    }
    await prefs.setString(_customApiUrlKey, cleanedUrl);
    print('🌐 URL API personnalisée sauvegardée: $cleanedUrl');
  }

  Future<String?> getCustomUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_customApiUrlKey);
  }

  Future<void> clearCustomUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customApiUrlKey);
    print('🌐 URL API personnalisée effacée');
  }

  Future<void> saveLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
  }

  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncString = prefs.getString(_lastSyncKey);
    if (lastSyncString != null) {
      return DateTime.parse(lastSyncString);
    }
    return null;
  }

  Future<void> clearAllStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _secureStorage.deleteAll();
    print('🗑️ Tout le stockage effacé');
  }

  Future<void> saveCollectInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('collect_interval', minutes);
  }

  Future<int> getCollectInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('collect_interval') ?? 5;
  }

  Future<void> saveSyncInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sync_interval', minutes);
  }

  Future<int> getSyncInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('sync_interval') ?? 10;
  }

  Future<SharedPreferences> getPreferences() async {
    return await SharedPreferences.getInstance();
  }
}
