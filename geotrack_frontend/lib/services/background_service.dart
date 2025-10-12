import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geotrack_frontend/services/storage_service.dart';

import 'auto_collect_service.dart';
import 'notification_service.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // Configuration du service
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: NotificationService.CHANNEL_ID,
      initialNotificationTitle: 'GeoTrack Service',
      initialNotificationContent: 'GPS collection service in progress...',
      foregroundServiceNotificationId: NotificationService.SERVICE_NOTIFICATION_ID,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );

  // Démarrer le service
  service.startService();
}

// Fonction de background pour iOS
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

// Fonction principale du service
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  print("-------------on Start--------------------");
  WidgetsFlutterBinding.ensureInitialized();

  //  Mettre immédiatement le service en foreground
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();

    // Afficher une notif tout de suite
    await NotificationService.showPersistentNotification(
      title: "GeoTrack Service",
      content: "Active GPS collection service",
    );

    // Gérer les events foreground/background
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();

    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  // Gérer l’arrêt du service
  service.on('stopService').listen((event) {
    service.stopSelf();
    NotificationService.showPersistentNotification(
      title: "GeoTrack Service",
      content: "GPS collection service stopped",
    );

  });

  // Ensuite seulement charger ton .env
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    print("Erreur lors du chargement de .env: $e");
  }

  // Démarrer tes tâches périodiques
  startPeriodicTasks(service);
}

void startPeriodicTasks(ServiceInstance service) async {
  // Lire les intervalles depuis le stockage
  final config = await StorageService().getConfig();

  // Timer pour la collecte GPS (intervalle configuré)
  Timer.periodic(Duration(seconds: config.collectionInterval ), (timer) async {
      await AutoCollectService.collectGpsDataBackground();
  });

  // Timer pour la synchronisation (intervalle configuré)
  Timer.periodic(Duration(seconds:config.sendInterval), (
      timer,
      ) async {
    await AutoCollectService.syncGpsDataBackground();

  });

  // Timer pour la synchronisation de config
  // celui ci est en minutes.
  Timer.periodic(Duration(minutes: config.configSyncInterval), (
      timer,
      ) async {
    await AutoCollectService.refetchConfig();
  });
}