import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geotrack_frontend/app.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_background_service_ios/flutter_background_service_ios.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geotrack_frontend/services/background_task_scheduler.dart';
import 'package:geotrack_frontend/services/auto_collect_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Charger les variables d'environnement
  await dotenv.load(fileName: ".env");

  print('🚀 App starting with API: ${dotenv.env['API_BASE_URL']}');

  runApp(const GeoTrackApp());
}

// Fonction pour démarrer le service background après authentification
Future<void> startBackgroundServices() async {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      // Vérifier l'authentification avant de démarrer
      final storageService = StorageService();
      final token = await storageService.getToken();

      if (token != null && token.isNotEmpty) {
        print('✅ Démarrage des services background après authentification');

        // Démarrage du service principal
        await _startMainBackgroundService();

        // Planification des tâches périodiques
        await BackgroundTaskScheduler.schedulePeriodicTasks();
      } else {
        print(
          '⚠️ Impossible de démarrer les services background: utilisateur non authentifié',
        );
      }
    } catch (e) {
      print('⚠️ Failed to start background services: $e');
    }
  }
}

// Fonction pour arrêter tous les services background
Future<void> stopBackgroundServices() async {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      // Arrêter le service principal
      final service = FlutterBackgroundService();
      service.invoke('stopService');

      // Annuler toutes les tâches planifiées
      await BackgroundTaskScheduler.cancelAllTasks();

      print('🛑 Tous les services background ont été arrêtés');
    } catch (e) {
      print('⚠️ Failed to stop background services: $e');
    }
  }
}

Future<void> _startMainBackgroundService() async {
  final service = FlutterBackgroundService();

  // Configuration corrigée selon la dernière API du plugin
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onServiceStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'geotrack_channel',
      initialNotificationTitle: 'GeoTrack Service',
      initialNotificationContent: 'Service GPS actif',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: _onServiceStart,
      onBackground: _onIosBackground,
    ),
  );

  // Vérifier si le service tourne déjà
  final isRunning = await service.isRunning();
  if (!isRunning) {
    await service.startService();
    print('✅ Service background initialisé et démarré');
  } else {
    print('ℹ️ Service background déjà en cours d\'exécution');
  }
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Vérifier l'authentification
  final storageService = StorageService();
  final token = await storageService.getToken();

  if (token == null || token.isEmpty) {
    print('⚠️ iOS Background: User not authenticated');
    return false;
  }

  return true;
}

@pragma('vm:entry-point')
void _onServiceStart(ServiceInstance service) async {
  // Configuration pour Android
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });

    // Configurer la notification persistante
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "GeoTrack Service",
        content: "Collecte GPS active - Toujours en cours",
      );
    }
  }

  // Écouter les commandes
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('updateNotification').listen((event) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: event?['title'] ?? "GeoTrack Service",
        content: event?['content'] ?? "Service actif",
      );
    }
  });

  // Démarrer le cœur du service
  await _startServiceCore(service);
}

Future<void> _startServiceCore(ServiceInstance service) async {
  print('⏰ Démarrage du cœur du service background');

  // Initialiser le stockage
  final storageService = StorageService();
  final token = await storageService.getToken();

  if (token == null || token.isEmpty) {
    print('⚠️ Service core: User not authenticated, pausing tasks');
    return;
  }

  // Initialiser les intervalles
  final prefs = await SharedPreferences.getInstance();
  int collectInterval = prefs.getInt('collect_interval') ?? 5;
  int syncInterval = prefs.getInt('sync_interval') ?? 10;

  // S'assurer que les intervalles sont valides
  collectInterval = collectInterval < 1 ? 5 : collectInterval;
  syncInterval = syncInterval < 1 ? 10 : syncInterval;

  print(
    '⏰ Intervalles - Collecte: ${collectInterval}min, Sync: ${syncInterval}min',
  );

  // Créer les timers
  final collectTimer = Timer.periodic(
    Duration(minutes: collectInterval),
    (timer) => _performBackgroundCollection(service),
  );

  final syncTimer = Timer.periodic(
    Duration(minutes: syncInterval),
    (timer) => _performBackgroundSync(service),
  );

  // Exécuter immédiatement une première tâche
  await _performBackgroundCollection(service);

  // Nettoyage à l'arrêt
  service.on('stopService').listen((event) {
    collectTimer.cancel();
    syncTimer.cancel();
  });

  // Redémarrer avec de nouveaux intervalles
  service.on('updateIntervals').listen((event) async {
    collectTimer.cancel();
    syncTimer.cancel();

    final newPrefs = await SharedPreferences.getInstance();
    final newCollectInterval = newPrefs.getInt('collect_interval') ?? 5;
    final newSyncInterval = newPrefs.getInt('sync_interval') ?? 10;

    Timer.periodic(
      Duration(minutes: newCollectInterval),
      (timer) => _performBackgroundCollection(service),
    );

    Timer.periodic(
      Duration(minutes: newSyncInterval),
      (timer) => _performBackgroundSync(service),
    );
  });
}

Future<void> _performBackgroundCollection(ServiceInstance service) async {
  try {
    print('📍 Background: Début de la collecte GPS...');

    // Vérifier à nouveau l'authentification
    final storageService = StorageService();
    final token = await storageService.getToken();

    if (token == null || token.isEmpty) {
      print('⚠️ Background collection: User not authenticated, skipping');
      return;
    }

    // Utiliser directement AutoCollectService
    await AutoCollectService.collectGpsDataBackground();

    // Mettre à jour la notification
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "GeoTrack Service",
        content:
            "Dernière collecte: ${DateTime.now().toString().substring(11, 16)}",
      );
    }

    print('✅ Background collection completed successfully');
  } catch (e) {
    print('❌ Background collection error: $e');

    // En cas d'erreur, attendre un peu avant de réessayer
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "GeoTrack Service",
        content: "Erreur de collecte - Réessai en cours",
      );
    }
  }
}

Future<void> _performBackgroundSync(ServiceInstance service) async {
  try {
    print('🔄 Background: Début de la synchronisation...');

    // Vérifier l'authentification
    final storageService = StorageService();
    final token = await storageService.getToken();

    if (token == null || token.isEmpty) {
      print('⚠️ Background sync: User not authenticated, skipping');
      return;
    }

    // Utiliser directement AutoCollectService
    await AutoCollectService.syncGpsDataBackground();

    // Mettre à jour la notification
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "GeoTrack Service",
        content:
            "Dernière sync: ${DateTime.now().toString().substring(11, 16)}",
      );
    }

    print('✅ Background sync completed successfully');
  } catch (e) {
    print('❌ Background sync error: $e');
  }
}

// Fonction pour mettre à jour les intervalles de service
Future<void> updateBackgroundServiceIntervals() async {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();

      if (isRunning) {
        service.invoke('updateIntervals');
        print('🔄 Intervalles du service background mis à jour');
      }
    } catch (e) {
      print('⚠️ Failed to update service intervals: $e');
    }
  }
}

// Fonction pour envoyer une notification au service
Future<void> sendNotificationToService(String title, String content) async {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();

      if (isRunning) {
        service.invoke('updateNotification', {
          'title': title,
          'content': content,
        });
      }
    } catch (e) {
      print('⚠️ Failed to send notification to service: $e');
    }
  }
}
