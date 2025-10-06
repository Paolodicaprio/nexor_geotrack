import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geotrack_frontend/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      notificationChannelId: 'geotrack_channel',
      initialNotificationTitle: 'GeoTrack Service',
      initialNotificationContent: 'GPS collection service in progress...',
      foregroundServiceNotificationId: 888,
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
      // NotificationService.showPersistentNotification(
      //   title: "GeoTrack Service",
      //   content: "Service de collecte GPS actif",
      // );
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
  // Lire les intervalles depuis SharedPreferences
  final prefs = await SharedPreferences.getInstance();

  // Timer pour la collecte GPS (intervalle configuré)
  Timer.periodic(Duration(minutes: prefs.getInt('collect_interval') ?? (Constants.defaultCollectionInterval ~/60)), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        print("--------collect from foreground service--------");

        await AutoCollectService.collectGpsDataBackground();
        // await NotificationService.showPersistentNotification(
        //   title: "GeoTrack - Collecte GPS",
        //   content: "Dernière collecte: ${DateTime.now().toString().substring(11, 16)}",
        // );
      }
    } else {
      await AutoCollectService.collectGpsDataBackground();
    }
  });

  // Timer pour la synchronisation (intervalle configuré)
  Timer.periodic(Duration(minutes: prefs.getInt('sync_interval') ?? (Constants.defaultSendInterval ~/60)), (
      timer,
      ) async {
    await AutoCollectService.syncGpsDataBackground();

    // Mettre à jour la notification après synchronisation
    if (service is AndroidServiceInstance &&
        await service.isForegroundService()) {
      // NotificationService.showPersistentNotification(
      //   title: "GeoTrack Service",
      //   content:
      //   "Dernière sync: ${DateTime.now().toString().substring(11, 16)}",
      // );
    }
  });

  // Timer pour la synchronisation de config
  Timer.periodic(Duration(minutes: prefs.getInt('config_sync_interval') ?? Constants.defaultConfigSyncInterval), (
      timer,
      ) async {
    await AutoCollectService.refetchConfig();
    // Mettre à jour la notification après synchronisation
    if (service is AndroidServiceInstance &&
        await service.isForegroundService()) {
      // NotificationService.showPersistentNotification(
      //   title: "GeoTrack Service",
      //   content:
      //   "Dernière Synchronisation de config: ${DateTime.now().toString().substring(11, 16)}",
      // );
    }
  });
}