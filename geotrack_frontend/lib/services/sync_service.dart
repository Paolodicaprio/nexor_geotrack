import 'package:geotrack_frontend/models/gps_data_model.dart';
import 'package:geotrack_frontend/services/api_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';

class SyncService {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();

  Future<void> syncPendingData() async {
    try {
      final pendingData = await _storageService.getPendingGpsData();
      final token = await _storageService.getToken();

      if (token == null || token.isEmpty) {
        print('❌ No auth token available for sync');
        throw Exception('Not authenticated');
      }

      if (pendingData.isEmpty) {
        print('✅ No pending data to sync');
        return;
      }

      print('🔄 Starting sync for ${pendingData.length} pending items');

      final List<GpsData> successfullySynced = [];

      for (final data in pendingData) {
        try {
          print('📤 Syncing data: ${data.idname} at ${data.datetime}');

          // Envoyer les données à l'API
          final syncedData = await _apiService.sendGpsData(data);

          print('✅ Data synced successfully with ID: ${syncedData.id}');

          // Marquer comme synchronisé et sauvegarder
          successfullySynced.add(syncedData.copyWith(synced: true));
        } catch (e) {
          print('❌ Failed to sync data: $e');
          // Continuer avec les autres données
        }
      }

      // Traiter les données synchronisées avec succès
      for (final syncedData in successfullySynced) {
        try {
          // Supprimer la version non synchronisée
          await _storageService.removePendingGpsDataById(syncedData);

          // Sauvegarder la version synchronisée
          await _storageService.saveSyncedGpsData(syncedData);
        } catch (e) {
          print('❌ Error processing synced data: $e');
        }
      }

      print(
        '✅ Sync completed: ${successfullySynced.length}/${pendingData.length} data synced',
      );
    } catch (e) {
      print('❌ Sync failed: $e');
      // Ne pas propager l'erreur pour éviter de casser le flux
    }
  }

  Future<void> addDataToSyncQueue(GpsData data) async {
    await _storageService.savePendingGpsData(data);
  }

  Future<int> getPendingSyncCount() async {
    final pendingData = await _storageService.getPendingGpsData();
    return pendingData.length;
  }

  // Synchronisation forcée (manuel)
  Future<Map<String, dynamic>> forceSync() async {
    final pendingCount = await getPendingSyncCount();

    if (pendingCount == 0) {
      return {'success': true, 'message': 'No data to sync', 'synced_count': 0};
    }

    try {
      await syncPendingData();
      final newCount = await getPendingSyncCount();

      return {
        'success': true,
        'message': 'Sync completed successfully',
        'synced_count': pendingCount - newCount,
        'remaining': newCount,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Sync failed: $e',
        'synced_count': 0,
      };
    }
  }
}
