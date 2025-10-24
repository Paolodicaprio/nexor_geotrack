import 'package:geolocator/geolocator.dart';
import 'package:geotrack_frontend/services/api_service.dart';
import 'package:geotrack_frontend/services/auth_service.dart';
import 'package:geotrack_frontend/services/safe_http.dart';
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
      await service._storageService.setLastCollectionTime(DateTime.now());

      print('📍 Donnée GPS collectées: ${location.lat}, ${location.lon}');
    } catch (e) {
      print('❌ Erreur collecte GPS: $e');
    }
  }

  static Future<void> syncGpsDataBackground({bool retry=false}) async {
    final service = AutoCollectService();
    //  on reload les données dans le cas ou des configurations ont changé depuis l'ui?
    service._storageService.reloadStorage();
    try {
      final pendingCount = await service._syncService.getPendingSyncCount();
      if (pendingCount > 0) {
        await service._syncService.syncPendingData();
        print('✅ Synchronisation réussie: $pendingCount données');
      }
    } catch (e) {
      print('❌ Erreur synchronisation: $e');
      /* dans le cas d'une reconnexion , la fonction est appelé avec retry= true
       donc si la reconnexion echoue, on remplace le CustomHttpException par une Exception normale
       afin d'eviter encore une autre reconnexion  */
      if (e is CustomHttpException && retry){
        print("bloc executé---------------");
        throw Exception(e.toString());
      }else{
        rethrow;
      }
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

  static Future<void> refetchConfig({bool retry = false})async{
    try{
      final config = await ApiService().getConfig();
      await StorageService().saveConfig(config);
    }catch(e){
      print(e);
      /* dans le cas d'une reconnexion , la fonction est appelé avec retry= true
       donc si la reconnexion echoue, on remplace le CustomHttpException par une Exception normale
       afin d'eviter encore une autre reconnexion  */
      if (e is CustomHttpException && retry){
        throw Exception(e.toString());
      }else{
        rethrow;
      }
    }
  }
}
