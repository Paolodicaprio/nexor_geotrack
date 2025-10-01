import 'package:geotrack_frontend/models/gps_data_model.dart';
import 'package:geotrack_frontend/services/api_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';

import 'notification_service.dart';

class SyncService {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();

  Future<void> syncPendingData() async {
    try {
      final pendingData = await _storageService.getPendingGpsData();
      final token = await _storageService.getToken();

      if (token == null) {
        print('❌ No auth token available for sync');
        return;
      }

      if (pendingData.isEmpty) {
        print('✅ No pending data to sync');
        return;
      }

      final List<GpsData> successfullySynced = [];

// Filtrer et préparer les données valides
      final List<Map<String, dynamic>> jsonList = [];
      for (final data in pendingData) {
        if (data.id == null) {
          print('❌ Failed to sync data: id is null, skipping this entry.');
          continue;
        }
        jsonList.add(data.toApiJson());
      }

// Envoyer la liste d’un coup si elle n’est pas vide
      if (jsonList.isNotEmpty) {
        try {
          await _apiService.sendGpsDataJsonList(jsonList); // <-- nouvelle méthode pour envoyer la liste

          // Marquer toutes les données comme synchronisées
          for (final data in pendingData) {
            if (data.id != null) {
              successfullySynced.add(data.copyWith(synced: true));
            }
          }

          print('✅ ${successfullySynced.length} data entries synced successfully.');
        } catch (e) {
          // Afficher la notification
          NotificationService.showTemporaryNotification(
            title: "Synchronisation failed",
            content: e.toString().replaceFirst("Exception: ", ""),
          );
          print('❌ Failed to sync GPS data list: $e');
        }
      }
      // _apiService.resetErrorShown();

      // Supprimer toutes les données synchronisées de la liste d'attente
      for (final syncedData in successfullySynced) {
        await _storageService.removePendingGpsData(syncedData.id!);
        // Sauvegarder dans les données synchronisées
        await _storageService.saveSyncedGpsData(syncedData);
      }

      print('✅ Sync completed: ${successfullySynced.length} data synced');
    } catch (e) {
      print('❌ Sync failed: $e');
    }
  }

  Future<void> addDataToSyncQueue(GpsData data) async {
    await _storageService.savePendingGpsData(data);
  }

  Future<int> getPendingSyncCount() async {
    final pendingData = await _storageService.getPendingGpsData();
    return pendingData.length;
  }
}
