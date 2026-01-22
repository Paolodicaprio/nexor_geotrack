import 'package:flutter/material.dart';
import 'package:geotrack_frontend/models/gps_data_model.dart';
import 'package:geotrack_frontend/services/api_service.dart';
import 'package:geotrack_frontend/services/safe_http.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:geotrack_frontend/utils/global_keys.dart';

import 'auth_service.dart';
import 'notification_service.dart';

class SyncService {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();

  //TODO: Diviser en chunk de 1000 données
  Future<void> syncPendingData() async {
    try {
      final pendingData = await _storageService.getPendingGpsData();
      if (pendingData.isEmpty) {
        print('✅ No pending data to sync');
        return;
      }
      
      final token = await _storageService.getToken();
      final username = await _storageService.getUserUsername();
      final password = await _storageService.getPassword();
      
      // Don't attempt sync without valid auth
      if (token == null || token.isEmpty) {
        if (username == null || password == null) {
          print('❌ No auth credentials available for sync');
          throw CustomHttpException('No valid authentication', statusCode: 401);
        }
        // Let the caller handle reconnection
        throw CustomHttpException('Token expired', statusCode: 401);
      }

      final List<Map<String, dynamic>> jsonList = pendingData
          .map((data) => data.toApiJson())
          .toList();

      if (jsonList.isNotEmpty) {
        try {
          await _apiService.sendGpsDataJsonList(jsonList);

          await _storageService.markAllAsSynced(pendingData);

          print('✅ ${pendingData.length} data entries synced and marked successfully.');
        } catch (e) {
          scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ));
          print('❌ Failed to sync GPS data list: $e');
          throw e;
        }
      }
    } catch (e) {
      print('❌ Sync failed: $e');
      rethrow;
    }
  }




  Future<int> getPendingSyncCount() async {
    final pendingData = await _storageService.getPendingGpsData();
    return pendingData.length;
  }
}
