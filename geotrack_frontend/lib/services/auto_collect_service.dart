import 'package:shared_preferences/shared_preferences.dart';
import 'package:geotrack_frontend/services/gps_service.dart';
import 'package:geotrack_frontend/services/sync_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';

class AutoCollectService {
  static final GpsService _gpsService = GpsService();
  static final SyncService _syncService = SyncService();
  static final StorageService _storageService = StorageService();

  static Future<void> collectGpsDataBackground() async {
    try {
      print('📍 Starting GPS data collection...');

      // Vérifier les permissions
      final hasPermission = await _gpsService.checkPermission();
      if (!hasPermission) {
        print('⚠️ Location permissions not granted');
        return;
      }

      // Récupérer la localisation
      final location = await _gpsService.getCurrentLocation();
      print(
        '📍 Location obtained: ${location.latitude}, ${location.longitude}',
      );

      // Sauvegarder localement
      await _storageService.savePendingGpsData(location);

      // Sauvegarder le timestamp de la dernière collecte
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'last_collection',
        DateTime.now().toIso8601String(),
      );

      print(
        '✅ GPS data collected and saved: ${location.latitude}, ${location.longitude}',
      );
    } catch (e) {
      print('❌ GPS collection error: $e');
    }
  }

  static Future<void> syncGpsDataBackground() async {
    try {
      print('🔄 Starting background sync...');

      // VÉRIFIER SI L'UTILISATEUR EST AUTHENTIFIÉ
      final token = await _storageService.getToken();
      if (token == null || token.isEmpty) {
        print('⚠️ User not authenticated, skipping background sync');
        return;
      }

      final pendingCount = await _syncService.getPendingSyncCount();
      if (pendingCount > 0) {
        print('🔄 Syncing $pendingCount pending items...');
        await _syncService.syncPendingData();
        print('✅ Background sync completed: $pendingCount items processed');
      } else {
        print('✅ No pending data to sync');
      }
    } catch (e) {
      print('❌ Background sync error: $e');
    }
  }

  // Méthodes manuelles
  static Future<void> manualCollect() async {
    await collectGpsDataBackground();
  }

  static Future<void> manualSync() async {
    await syncGpsDataBackground();
  }
}
