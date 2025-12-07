// background_service_manager.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geotrack_frontend/services/auto_collect_service.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackgroundServiceManager {
  static Future<void> initializeService() async {
    if (kIsWeb) return;

    final service = FlutterBackgroundService();

    // Vérifier si le service est déjà configuré
    final isRunning = await service.isRunning();

    if (!isRunning) {
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
          autoStart: false,
          onForeground: onStart,
          onBackground: onIosBackground,
        ),
      );

      print('✅ Service background initialisé (prêt à démarrer)');
    }
  }

  static Future<void> startService() async {
    if (kIsWeb) return;

    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();

      if (!isRunning) {
        // S'assurer que le service est configuré
        await initializeService();
        await service.startService();
        print('✅ Service background démarré');
      } else {
        print('ℹ️ Service background déjà en cours d\'exécution');
      }
    } catch (e) {
      print('❌ Erreur lors du démarrage du service: $e');
    }
  }

  static Future<void> stopService() async {
    if (kIsWeb) return;

    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();

      if (isRunning) {
        service.invoke('stopService');
        print('✅ Service background arrêté');
      }
    } catch (e) {
      print('❌ Erreur lors de l\'arrêt du service: $e');
    }
  }

  static Future<bool> isServiceRunning() async {
    if (kIsWeb) return false;

    try {
      final service = FlutterBackgroundService();
      return await service.isRunning();
    } catch (e) {
      print('❌ Erreur lors de la vérification du service: $e');
      return false;
    }
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  // Vérifier l'authentification
  final storageService = StorageService();
  final token = await storageService.getToken();

  return token != null && token.isNotEmpty;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  print('🔄 Service background démarré avec succès');

  // Configuration Android
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });

    // Configurer la notification
    service.setForegroundNotificationInfo(
      title: "GeoTrack Service",
      content: "Collecte GPS active",
    );
  }

  // Démarrer les tâches périodiques
  await _startBackgroundTasks(service);
}

Future<void> _startBackgroundTasks(ServiceInstance service) async {
  print('⏰ Démarrage des tâches périodiques');

  try {
    // Charger les intervalles
    final prefs = await SharedPreferences.getInstance();
    int collectInterval = prefs.getInt('collect_interval') ?? 5;
    int syncInterval = prefs.getInt('sync_interval') ?? 10;

    // Assurer des valeurs minimales
    collectInterval = collectInterval < 1 ? 5 : collectInterval;
    syncInterval = syncInterval < 1 ? 10 : syncInterval;

    print(
      '📊 Intervalles configurés: collecte=$collectInterval min, sync=$syncInterval min',
    );

    // Timer pour la collecte
    Timer.periodic(Duration(minutes: collectInterval), (timer) async {
      await _performBackgroundCollection(service);
    });

    // Timer pour la synchronisation
    Timer.periodic(Duration(minutes: syncInterval), (timer) async {
      await _performBackgroundSync(service);
    });

    // Première exécution immédiate
    await _performBackgroundCollection(service);
  } catch (e) {
    print('❌ Erreur lors du démarrage des tâches: $e');
  }
}

Future<void> _performBackgroundCollection(ServiceInstance service) async {
  try {
    print('📍 Tâche background: Collecte GPS...');

    // Vérifier l'authentification
    final storageService = StorageService();
    final token = await storageService.getToken();

    if (token != null && token.isNotEmpty) {
      await AutoCollectService.collectGpsDataBackground();
      print('✅ Collecte background terminée');

      // Mettre à jour la notification
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: "GeoTrack Service",
          content:
              "Dernière collecte: ${DateTime.now().toString().substring(11, 16)}",
        );
      }
    } else {
      print('⚠️ Collecte ignorée: utilisateur non authentifié');
    }
  } catch (e) {
    print('❌ Erreur lors de la collecte: $e');
  }
}

Future<void> _performBackgroundSync(ServiceInstance service) async {
  try {
    print('🔄 Tâche background: Synchronisation...');

    // Vérifier l'authentification
    final storageService = StorageService();
    final token = await storageService.getToken();

    if (token != null && token.isNotEmpty) {
      await AutoCollectService.syncGpsDataBackground();
      print('✅ Synchronisation background terminée');
    } else {
      print('⚠️ Synchronisation ignorée: utilisateur non authentifié');
    }
  } catch (e) {
    print('❌ Erreur lors de la synchronisation: $e');
  }
}
