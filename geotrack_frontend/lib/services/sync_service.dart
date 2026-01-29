import 'package:flutter/material.dart';
import 'package:geotrack_frontend/models/gps_data_model.dart';
import 'package:geotrack_frontend/services/api_service.dart';
import 'package:geotrack_frontend/services/safe_http.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:geotrack_frontend/utils/constants.dart';
import 'package:geotrack_frontend/utils/global_keys.dart';

import 'auth_service.dart';
import 'notification_service.dart';

class SyncService {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();

  /// Sync pending GPS data with automatic chunking for large payloads
  /// Handles 413 Payload Too Large by splitting into smaller chunks
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

      // Sync in chunks to avoid 413 Payload Too Large
      await _syncInChunks(pendingData, Constants.gpsBatchChunkSize);
      
    } catch (e) {
      print('❌ Sync failed: $e');
      rethrow;
    }
  }

  /// Sync data in chunks, with automatic retry using smaller chunks on 413 error
  Future<void> _syncInChunks(List<GpsData> pendingData, int chunkSize) async {
    final totalItems = pendingData.length;
    int syncedCount = 0;
    int currentIndex = 0;
    
    print('📦 Starting chunked sync: $totalItems items in chunks of $chunkSize');
    
    while (currentIndex < totalItems) {
      final endIndex = (currentIndex + chunkSize > totalItems) 
          ? totalItems 
          : currentIndex + chunkSize;
      final chunk = pendingData.sublist(currentIndex, endIndex);
      final jsonList = chunk.map((data) => data.toApiJson()).toList();
      
      try {
        await _apiService.sendGpsDataJsonList(jsonList);
        await _storageService.markAllAsSynced(chunk);
        syncedCount += chunk.length;
        print('✅ Chunk synced: ${chunk.length} items (${syncedCount}/$totalItems total)');
        currentIndex = endIndex;
        
      } on PayloadTooLargeException catch (e) {
        // 413 error - try with smaller chunk size
        final smallerChunkSize = Constants.gpsBatchChunkSizeOnPayloadTooLarge;
        if (chunkSize <= smallerChunkSize) {
          // Already at minimum chunk size, fail this chunk
          print('❌ Payload still too large even with minimum chunk size');
          _showSyncError('Data chunk too large to sync');
          throw e;
        }
        print('⚠️ Payload too large, retrying with smaller chunks ($smallerChunkSize)');
        // Retry remaining data with smaller chunks
        final remainingData = pendingData.sublist(currentIndex);
        await _syncInChunks(remainingData, smallerChunkSize);
        return; // Recursive call handles the rest
        
      } catch (e) {
        _showSyncError(e.toString());
        print('❌ Failed to sync chunk: $e');
        rethrow;
      }
    }
    
    print('✅ All $syncedCount data entries synced successfully.');
  }
  
  void _showSyncError(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.redAccent,
      duration: const Duration(seconds: 5),
    ));
  }




  Future<int> getPendingSyncCount() async {
    final pendingData = await _storageService.getPendingGpsData();
    return pendingData.length;
  }
}
