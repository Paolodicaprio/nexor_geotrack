import 'package:geotrack_frontend/models/gps_data_model.dart';
import 'package:geotrack_frontend/services/api_service.dart';
import 'package:geotrack_frontend/services/database_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';

class SyncService {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();
  final DatabaseService _databaseService = DatabaseService();

  Future<void> syncPendingData() async {
    try {
      final pendingData = await _databaseService.getPendingGpsData();
      final token = await _storageService.getToken();

      if (token == null || token.isEmpty) {
        print('❌ Pas de token d\'authentification pour la synchronisation');
        throw Exception('Non authentifié');
      }

      if (pendingData.isEmpty) {
        print('✅ Aucune donnée en attente à synchroniser');
        return;
      }

      print(
        '🔄 Début de synchronisation pour ${pendingData.length} données en attente',
      );

      final List<Map<String, dynamic>> successfullySynced = [];

      for (final data in pendingData) {
        try {
          print('📤 Synchronisation: ${data.idname} à ${data.datetime}');

          // Envoyer à l'API
          final syncedData = await _apiService.sendGpsData(data);

          print('✅ Donnée synchronisée avec ID: ${syncedData.id}');

          successfullySynced.add({
            'local_id': data.id,
            'api_id': syncedData.id,
          });
        } catch (e) {
          print('❌ Échec de synchronisation ${data.idname}: $e');
        }
      }

      // Marquer comme synchronisé
      if (successfullySynced.isNotEmpty) {
        await _databaseService.markMultipleAsSynced(successfullySynced);
        await _storageService.saveLastSyncTime();
      }

      print(
        '✅ Synchronisation terminée: ${successfullySynced.length}/${pendingData.length} données synchronisées',
      );
    } catch (e) {
      print('❌ Échec de synchronisation: $e');
    }
  }

  Future<Map<String, dynamic>> syncWithRetry({
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 2),
  }) async {
    int retryCount = 0;
    Duration delay = initialDelay;

    while (retryCount < maxRetries) {
      try {
        print('🔄 Tentative de synchronisation ${retryCount + 1}/$maxRetries');
        await syncPendingData();

        final pendingCount = await getPendingSyncCount();
        return {
          'success': true,
          'message': 'Synchronisation réussie',
          'synced_count': pendingCount,
          'attempts': retryCount + 1,
        };
      } catch (e) {
        retryCount++;
        print('❌ Tentative $retryCount échouée: $e');

        if (retryCount < maxRetries) {
          print('⏳ Nouvelle tentative dans ${delay.inSeconds} secondes...');
          await Future.delayed(delay);
          // Augmenter le délai pour la prochaine tentative (backoff exponentiel)
          delay = Duration(seconds: delay.inSeconds * 2);
        } else {
          return {
            'success': false,
            'message': 'Échec après $maxRetries tentatives: $e',
            'synced_count': 0,
            'attempts': retryCount,
          };
        }
      }
    }

    return {
      'success': false,
      'message': 'Échec de synchronisation',
      'synced_count': 0,
      'attempts': retryCount,
    };
  }

  Future<void> addDataToSyncQueue(GpsData data) async {
    await _databaseService.saveGpsData(data, synced: false);
  }

  Future<int> getPendingSyncCount() async {
    return await _databaseService.getPendingCount();
  }

  Future<Map<String, dynamic>> forceSync() async {
    final pendingCount = await getPendingSyncCount();

    if (pendingCount == 0) {
      return {
        'success': true,
        'message': 'Aucune donnée à synchroniser',
        'synced_count': 0,
      };
    }

    try {
      await syncPendingData();
      final newCount = await getPendingSyncCount();

      return {
        'success': true,
        'message': 'Synchronisation terminée avec succès',
        'synced_count': pendingCount - newCount,
        'remaining': newCount,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Échec de synchronisation: $e',
        'synced_count': 0,
      };
    }
  }
}
