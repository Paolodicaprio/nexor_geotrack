import 'package:shared_preferences/shared_preferences.dart';
import 'package:geotrack_frontend/services/gps_service.dart';
import 'package:geotrack_frontend/services/sync_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:geotrack_frontend/services/database_service.dart';

class AutoCollectService {
  static final GpsService _gpsService = GpsService();
  static final SyncService _syncService = SyncService();
  static final StorageService _storageService = StorageService();
  static final DatabaseService _databaseService = DatabaseService();

  static Future<void> collectGpsDataBackground() async {
    try {
      print('📍 Background: Collecte de données GPS...');

      final hasPermission = await _gpsService.checkPermission();
      if (!hasPermission) {
        print('⚠️ Permissions de localisation non accordées');
        return;
      }

      final location = await _gpsService.getCurrentLocation();
      print(
        '📍 Localisation obtenue: ${location.latitude}, ${location.longitude}',
      );

      await _databaseService.saveGpsData(location, synced: false);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'last_collection',
        DateTime.now().toIso8601String(),
      );

      print(
        '✅ Donnée GPS collectée et sauvegardée: ${location.latitude}, ${location.longitude}',
      );
    } catch (e) {
      print('❌ Erreur de collecte GPS: $e');
    }
  }

  static Future<void> syncGpsDataBackground() async {
    try {
      print('🔄 Background: Synchronisation des données...');

      final token = await _storageService.getToken();
      if (token == null || token.isEmpty) {
        print('⚠️ Utilisateur non authentifié, synchronisation ignorée');
        return;
      }

      final pendingCount = await _syncService.getPendingSyncCount();
      if (pendingCount > 0) {
        print('🔄 Synchronisation de $pendingCount données en attente...');
        await _syncService.syncPendingData();
        print('✅ Synchronisation terminée: $pendingCount données traitées');
      } else {
        print('✅ Aucune donnée en attente à synchroniser');
      }
    } catch (e) {
      print('❌ Erreur de synchronisation en arrière-plan: $e');
    }
  }

  static Future<void> manualCollect() async {
    try {
      await collectGpsDataBackground();
    } catch (e) {
      print('❌ Erreur de collecte manuelle: $e');
      rethrow;
    }
  }

  static Future<void> manualSync() async {
    try {
      await syncGpsDataBackground();
    } catch (e) {
      print('❌ Erreur de synchronisation manuelle: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getCollectionStats() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingCount = await _databaseService.getPendingCount();
    final lastCollection = prefs.getString('last_collection');
    final lastSync = await _databaseService.getLastSyncTime();

    final collectInterval = prefs.getInt('collect_interval') ?? 5;
    final syncInterval = prefs.getInt('sync_interval') ?? 10;

    return {
      'pending_count': pendingCount,
      'last_collection':
          lastCollection != null ? DateTime.parse(lastCollection) : null,
      'last_sync': lastSync,
      'next_collection': DateTime.now().add(Duration(minutes: collectInterval)),
      'next_sync': DateTime.now().add(Duration(minutes: syncInterval)),
      'collect_interval': collectInterval,
      'sync_interval': syncInterval,
    };
  }
}
