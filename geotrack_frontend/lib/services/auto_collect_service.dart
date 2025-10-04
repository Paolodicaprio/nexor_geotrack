import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geotrack_frontend/services/gps_service.dart';
import 'package:geotrack_frontend/services/sync_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';

class AutoCollectService {
  final GpsService _gpsService = GpsService();
  final SyncService _syncService = SyncService();
  final StorageService _storageService = StorageService();

  static Future<void> collectGpsDataBackground() async {
    final service = AutoCollectService();
    try {
      // VÉRIFIER SI LA LOCALISATION EST ACTIVÉE
      final isLocationEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isLocationEnabled) {
        print('📍 Localisation désactivée - collecte annulée');
        return;
      }

      // VÉRIFIER LES PERMISSIONS
      final hasPermission = await service._gpsService.checkPermission();
      if (!hasPermission) {
        print('📍 Permissions de localisation refusées - collecte annulée');
        return;
      }
      final location = await service._gpsService.getCurrentLocation();
      await service._storageService.savePendingGpsData(location);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'last_collection',
        DateTime.now().toIso8601String(),
      );

      print('📍 Donnée GPS collectée: ${location.lat}, ${location.lon}');
    } catch (e) {
      print('❌ Erreur collecte GPS: $e');
    }
  }

  static Future<void> syncGpsDataBackground() async {
    final service = AutoCollectService();
    try {
      final pendingCount = await service._syncService.getPendingSyncCount();
      if (pendingCount > 0) {
        await service._syncService.syncPendingData();
        print('✅ Synchronisation réussie: $pendingCount données');
      }
    } catch (e) {
      print('❌ Erreur synchronisation: $e');
    }
  }

  // Ces méthodes peuvent être supprimées car elles sont redondantes
  static Future<void> collectGpsData() async {
    await collectGpsDataBackground();
  }

  static Future<void> syncGpsData() async {
    await syncGpsDataBackground();
  }

  Future<Map<String, dynamic>> getCollectionStats() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingData = await _storageService.getPendingGpsData();
    final lastCollection = prefs.getString('last_collection');

    return {
      'pending_count': pendingData.length,
      'last_collection':
          lastCollection != null ? DateTime.parse(lastCollection) : null,
      'next_collection': DateTime.now().add(const Duration(minutes: 5)),
      'next_sync': DateTime.now().add(const Duration(minutes: 10)),
    };
  }
}
