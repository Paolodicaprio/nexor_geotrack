import 'package:geolocator/geolocator.dart';
import 'package:geotrack_frontend/models/gps_data_model.dart';

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

  Future<GpsData> getCurrentLocation() async {
    try {
      final hasPermission = await checkPermission();
      if (!hasPermission) {
        throw Exception('Location permissions denied');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      // Utiliser les nouveaux noms de paramètres du constructeur GpsData
      return GpsData(
        idname: await _getDeviceId(),
        latitude: position.latitude,
        longitude: position.longitude,
        datetime: DateTime.now(),
      );
    } catch (e) {
      throw Exception('Failed to get location: $e');
    }
  }

  Future<String> _getDeviceId() async {
    // Utiliser un identifiant unique pour l'appareil
    // Vous pouvez le rendre configurable ou utiliser l'ID du device
    return 'MOBILE_${DateTime.now().millisecondsSinceEpoch}';
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
