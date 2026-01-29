import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:geotrack_frontend/models/gps_data_model.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:uuid/uuid.dart';

class GpsService {
  Future<bool> checkPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Get current GPS location with offline-friendly settings
  /// Uses longer timeout and fallback to last known position when offline
  Future<GpsData> getCurrentLocation() async {
    try {
      final hasPermission = await checkPermission();
      if (!hasPermission) {
        throw Exception('Location permissions denied');
      }

      Position? position;
      
      try {
        // Use 'high' accuracy instead of 'best' - works better offline
        // 'best' relies heavily on A-GPS which requires internet
        // Increase timeout to 30s to allow pure GPS satellite lock when offline
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 30),
        );
      } on TimeoutException {
        // GPS timed out (common when offline) - try last known position
        print('⏱️ GPS timeout, trying last known position...');
        position = await Geolocator.getLastKnownPosition();
        
        if (position == null) {
          throw Exception('GPS timeout and no cached position available');
        }
        print('📍 Using last known position from ${DateTime.now().difference(position.timestamp ?? DateTime.now()).inMinutes} minutes ago');
      }

      if (position.latitude < -90 ||
          position.latitude > 90 ||
          position.longitude < -180 ||
          position.longitude > 180) {
        throw Exception('Invalid location coordinates');
      }
      
      return GpsData(
        uuid: const Uuid().v4(),
        lat: position.latitude,
        lon: position.longitude,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      throw Exception('Failed to get location: $e');
    }
  }

  Future<String?> _getDeviceId() async {
    // Utiliser un identifiant unique pour l'appareil
    return await StorageService().getDeviceCode();
  }

  Stream<Position> getLocationStream() {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10, // meters
      ),
    );
  }
}
