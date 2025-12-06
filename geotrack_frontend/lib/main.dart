import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geotrack_frontend/app.dart';
import 'package:geotrack_frontend/services/auto_collect_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Charger les variables d'environnement
  await dotenv.load(fileName: ".env");

  print('🚀 App starting with API: ${dotenv.env['API_BASE_URL']}');

  // NE PAS initialiser le service background au démarrage
  // Il sera démarré manuellement après l'authentification

  runApp(const GeoTrackApp());
}

// Fonction pour démarrer le service background après authentification
Future<void> startBackgroundServiceIfNeeded() async {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();

      if (!isRunning) {
        await _initializeBackgroundService();
        print('✅ Background service started');
      } else {
        print('✅ Background service already running');
      }
    } catch (e) {
      print('⚠️ Failed to start background service: $e');
    }
  }
}

// Fonction pour arrêter le service background
Future<void> stopBackgroundService() async {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        service.invoke('stopService');
        print('🛑 Background service stopped');
      }
    } catch (e) {
      print('⚠️ Failed to stop background service: $e');
    }
  }
}

Future<void> _initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // Configuration SIMPLIFIÉE du service
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false, // Ne pas démarrer automatiquement
      isForegroundMode: true,
      notificationChannelId: 'geotrack_channel',
      initialNotificationTitle: 'GeoTrack Service',
      initialNotificationContent: 'Service GPS actif',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false, // Ne pas démarrer automatiquement
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );

  // Démarrer le service
  await service.startService();
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Vérifier l'authentification avant de faire quoi que ce soit
  final storageService = StorageService();
  final token = await storageService.getToken();

  if (token == null || token.isEmpty) {
    print('⚠️ iOS Background: User not authenticated');
    return false;
  }

  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Initialiser pour Android
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });

    // Configurer la notification de base
    service.setForegroundNotificationInfo(
      title: "GeoTrack Service",
      content: "Service GPS actif",
    );
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Démarrer les tâches périodiques
  await startPeriodicTasks(service);
}

Future<void> startPeriodicTasks(ServiceInstance service) async {
  print('⏰ Starting periodic tasks in background service');

  // Attendre un peu pour que tout soit initialisé
  await Future.delayed(const Duration(seconds: 2));

  // Vérifier l'authentification avant de continuer
  final storageService = StorageService();
  final token = await storageService.getToken();

  if (token == null || token.isEmpty) {
    print('⚠️ Background service: User not authenticated, stopping tasks');

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "GeoTrack Service",
        content: "En attente d'authentification...",
      );
    }

    return;
  }

  // Charger les intervalles depuis SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final collectInterval = prefs.getInt('collect_interval') ?? 5;
  final syncInterval = prefs.getInt('sync_interval') ?? 10;

  print(
    '⏰ Intervals - Collect: ${collectInterval}min, Sync: ${syncInterval}min',
  );

  // Timer pour la collecte GPS
  Timer.periodic(Duration(minutes: collectInterval), (timer) async {
    try {
      // Vérifier à nouveau l'authentification
      final currentToken = await storageService.getToken();
      if (currentToken == null || currentToken.isEmpty) {
        print('⚠️ Background collection: User not authenticated, skipping');
        timer.cancel();
        return;
      }

      print('📍 Background: Collecting GPS data...');
      await AutoCollectService.collectGpsDataBackground();

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: "GeoTrack Service",
          content:
              "Dernière collecte: ${DateTime.now().toString().substring(11, 16)}",
        );
      }
    } catch (e) {
      print('❌ Background collection error: $e');
    }
  });

  // Timer pour la synchronisation
  Timer.periodic(Duration(minutes: syncInterval), (timer) async {
    try {
      // Vérifier à nouveau l'authentification
      final currentToken = await storageService.getToken();
      if (currentToken == null || currentToken.isEmpty) {
        print('⚠️ Background sync: User not authenticated, skipping');
        timer.cancel();
        return;
      }

      print('🔄 Background: Syncing data...');
      await AutoCollectService.syncGpsDataBackground();

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: "GeoTrack Service",
          content:
              "Dernière sync: ${DateTime.now().toString().substring(11, 16)}",
        );
      }
    } catch (e) {
      print('❌ Background sync error: $e');
    }
  });

  print('✅ Background service tasks started successfully');
}
