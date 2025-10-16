import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionResult {
  final bool locationWhenInUse;
  final bool locationAlways;
  final bool notification;
  final bool ignoreBatteryOptimizations;
  final bool systemAlertWindow;
  final bool locationServiceEnabled;
  final bool allGranted;

  PermissionResult({
    required this.locationWhenInUse,
    required this.locationAlways,
    required this.notification,
    required this.ignoreBatteryOptimizations,
    required this.systemAlertWindow,
    required this.locationServiceEnabled,
    required this.allGranted,
  });
}

Future<PermissionResult> requestPermissions() async {
  // 1️⃣ Vérifier si le service de localisation est activé
  bool locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!locationServiceEnabled) {
    // Ouvrir les paramètres pour activer le GPS
    await Geolocator.openLocationSettings();
    // Re-vérifier après ouverture
    locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
  }
  // Demander les permissions de localisation et notification de manière séquentielle
  final locationWhenInUse = await Permission.locationWhenInUse.request();
  final locationAlways = locationWhenInUse.isGranted
      ? await Permission.locationAlways.request()
      : PermissionStatus.denied;
  final notification = locationAlways.isGranted
      ? await Permission.notification.request()
      : PermissionStatus.denied;

  // Demander les permissions supplémentaires
  final additionalPermissions = await [
    Permission.ignoreBatteryOptimizations,
    Permission.systemAlertWindow,
  ].request();

  return PermissionResult(
    locationWhenInUse: locationWhenInUse.isGranted,
    locationAlways: locationAlways.isGranted,
    notification: notification.isGranted,
    ignoreBatteryOptimizations:
    additionalPermissions[Permission.ignoreBatteryOptimizations]?.isGranted ?? false,
    systemAlertWindow:
    additionalPermissions[Permission.systemAlertWindow]?.isGranted ?? false,
      locationServiceEnabled: locationServiceEnabled,
      allGranted: locationWhenInUse.isGranted &&
                locationAlways.isGranted &&
                notification.isGranted &&
                locationServiceEnabled &&
                additionalPermissions[Permission.ignoreBatteryOptimizations]!.isGranted );
}

Future<PermissionResult> checkPermissions() async {
  // Vérifier le statut actuel des permissions sans les demander
  final locationWhenInUse = await Permission.locationWhenInUse.status;
  final locationAlways = await Permission.locationAlways.status;
  final notification = await Permission.notification.status;
  final ignoreBatteryOptimizations = await Permission.ignoreBatteryOptimizations.status;
  final systemAlertWindow = await Permission.systemAlertWindow.status;
  final locationServiceEnabled = await Geolocator.isLocationServiceEnabled();


  return PermissionResult(
    locationWhenInUse: locationWhenInUse.isGranted,
    locationAlways: locationAlways.isGranted,
    notification: notification.isGranted,
    ignoreBatteryOptimizations: ignoreBatteryOptimizations.isGranted,
    systemAlertWindow: systemAlertWindow.isGranted,
    locationServiceEnabled: locationServiceEnabled,
    allGranted: locationWhenInUse.isGranted &&
                locationAlways.isGranted &&
                notification.isGranted &&
                ignoreBatteryOptimizations.isGranted &&
                locationServiceEnabled
  );
}
