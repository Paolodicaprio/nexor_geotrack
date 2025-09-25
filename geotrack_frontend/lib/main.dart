import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geotrack_frontend/app.dart';
import 'package:geotrack_frontend/services/auto_collect_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Charger les variables d'environnement
  await dotenv.load(fileName: ".env");

  // Initialiser le service background uniquement sur les plateformes mobiles
  if (!kIsWeb) {
    await initializeBackgroundService();
  }

  runApp(const GeoTrackApp());
}

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // Configuration du service
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
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
void onStart(ServiceInstance service) {
  // Pour Android, configurer le service foreground
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Démarrer les tâches périodiques
  startPeriodicTasks(service);
}

void startPeriodicTasks(ServiceInstance service) async {
  // Lire les intervalles depuis SharedPreferences
  final prefs = await SharedPreferences.getInstance();

  // Timer pour la collecte GPS (intervalle configuré)
  Timer.periodic(Duration(minutes: prefs.getInt('collect_interval') ?? 5), (
    timer,
  ) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        await AutoCollectService.collectGpsDataBackground();

        // Mettre à jour la notification
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: "GeoTrack Service",
            content:
                "Dernière collecte: ${DateTime.now().toString().substring(11, 16)}",
          );
        }
      }
    } else {
      await AutoCollectService.collectGpsDataBackground();
    }
  });

  // Timer pour la synchronisation (intervalle configuré)
  Timer.periodic(Duration(minutes: prefs.getInt('sync_interval') ?? 10), (
    timer,
  ) async {
    await AutoCollectService.syncGpsDataBackground();

    // Mettre à jour la notification après synchronisation
    if (service is AndroidServiceInstance &&
        await service.isForegroundService()) {
      service.setForegroundNotificationInfo(
        title: "GeoTrack Service",
        content:
            "Dernière sync: ${DateTime.now().toString().substring(11, 16)}",
      );
    }
  });

  // Initialiser la notification
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: "GeoTrack Service",
      content: "Service de collecte GPS démarré",
    );
  }
}
