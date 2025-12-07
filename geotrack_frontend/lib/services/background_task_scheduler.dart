import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:geotrack_frontend/services/auto_collect_service.dart';

class BackgroundTaskScheduler {
  static bool _initialized = false;
  static Timer? _healthCheckTimer;
  static Timer? _collectTimer;
  static Timer? _syncTimer;

  static Future<void> initialize() async {
    if (_initialized) return;

    print('🔄 Initialisation du planificateur de tâches background');
    _initialized = true;

    // Démarrer le vérificateur de santé
    _startHealthChecker();

    // Vérifier périodiquement l'authentification pour redémarrer les services si nécessaire
    Timer.periodic(const Duration(minutes: 5), (timer) async {
      await _checkAndRestartServicesIfNeeded();
    });
  }

  static Future<void> schedulePeriodicTasks() async {
    if (!kIsWeb) {
      await _scheduleTasks();
    }
  }

  static Future<void> _scheduleTasks() async {
    try {
      print('📱 Planification des tâches background');

      // Annuler les timers existants
      _collectTimer?.cancel();
      _syncTimer?.cancel();

      // Obtenir les intervalles
      final prefs = await SharedPreferences.getInstance();
      final collectInterval = prefs.getInt('collect_interval') ?? 5;
      final syncInterval = prefs.getInt('sync_interval') ?? 10;

      // Planifier une tâche de collecte à intervalle régulier
      _collectTimer = Timer.periodic(Duration(minutes: collectInterval), (
        timer,
      ) async {
        await _executeCollectionTask();
      });

      // Planifier une tâche de synchronisation
      _syncTimer = Timer.periodic(Duration(minutes: syncInterval), (
        timer,
      ) async {
        await _executeSyncTask();
      });

      print(
        '✅ Tâches planifiées avec intervalles: collecte=$collectInterval min, sync=$syncInterval min',
      );

      // Exécuter immédiatement une première tâche
      await _executeCollectionTask();
    } catch (e) {
      print('❌ Erreur de planification: $e');
    }
  }

  static Future<void> _executeCollectionTask() async {
    try {
      print('📍 Exécution de la tâche de collecte planifiée');

      // Vérifier l'authentification
      final storageService = StorageService();
      final token = await storageService.getToken();

      if (token != null && token.isNotEmpty) {
        await AutoCollectService.collectGpsDataBackground();
        print('✅ Tâche de collecte exécutée avec succès');

        // Mettre à jour le timestamp de dernière activité
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'last_collection_time',
          DateTime.now().toIso8601String(),
        );
      } else {
        print('⚠️ Tâche de collecte ignorée: utilisateur non authentifié');
      }
    } catch (e) {
      print('❌ Erreur d\'exécution de la tâche de collecte: $e');
    }
  }

  static Future<void> _executeSyncTask() async {
    try {
      print('🔄 Exécution de la tâche de synchronisation planifiée');

      // Vérifier l'authentification
      final storageService = StorageService();
      final token = await storageService.getToken();

      if (token != null && token.isNotEmpty) {
        await AutoCollectService.syncGpsDataBackground();
        print('✅ Tâche de synchronisation exécutée avec succès');

        // Mettre à jour le timestamp de dernière activité
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'last_sync_time',
          DateTime.now().toIso8601String(),
        );
      } else {
        print(
          '⚠️ Tâche de synchronisation ignorée: utilisateur non authentifié',
        );
      }
    } catch (e) {
      print('❌ Erreur d\'exécution de la tâche de synchronisation: $e');
    }
  }

  static void _startHealthChecker() {
    _healthCheckTimer?.cancel();

    _healthCheckTimer = Timer.periodic(const Duration(minutes: 15), (
      timer,
    ) async {
      print('🏥 Vérification de santé du service background');

      try {
        // Vérifier l'état du stockage
        final prefs = await SharedPreferences.getInstance();
        final lastCollectKey = 'last_background_collection';
        final lastCollect = prefs.getString(lastCollectKey);

        if (lastCollect != null) {
          final lastCollectTime = DateTime.parse(lastCollect);
          final diff = DateTime.now().difference(lastCollectTime);

          if (diff.inMinutes > 30) {
            print('⚠️ Pas de collecte depuis ${diff.inMinutes} minutes');
            // Tenter de redémarrer les services
            await _checkAndRestartServicesIfNeeded();
          }
        }

        // Mettre à jour le timestamp
        await prefs.setString(lastCollectKey, DateTime.now().toIso8601String());
      } catch (e) {
        print('❌ Erreur lors de la vérification de santé: $e');
      }
    });
  }

  static Future<void> _checkAndRestartServicesIfNeeded() async {
    try {
      final storageService = StorageService();
      final token = await storageService.getToken();

      if (token != null && token.isNotEmpty) {
        print('🔄 Vérification et redémarrage éventuel des services');

        // Vérifier le timestamp de la dernière activité
        final prefs = await SharedPreferences.getInstance();
        final lastActivityKey = 'last_background_activity';
        final lastActivity = prefs.getString(lastActivityKey);

        if (lastActivity != null) {
          final lastActivityTime = DateTime.parse(lastActivity);
          final diff = DateTime.now().difference(lastActivityTime);

          if (diff.inMinutes > 60) {
            print('⚠️ Service inactif depuis longtemps, redémarrage...');
            await schedulePeriodicTasks();
          }
        }

        await prefs.setString(
          lastActivityKey,
          DateTime.now().toIso8601String(),
        );
      }
    } catch (e) {
      print('❌ Erreur lors de la vérification des services: $e');
    }
  }

  static Future<void> cancelAllTasks() async {
    _healthCheckTimer?.cancel();
    _collectTimer?.cancel();
    _syncTimer?.cancel();

    _healthCheckTimer = null;
    _collectTimer = null;
    _syncTimer = null;

    print('🛑 Toutes les tâches planifiées ont été annulées');
  }

  static Future<void> updateTaskIntervals() async {
    print('🔄 Mise à jour des intervalles de tâches');
    await cancelAllTasks();
    await schedulePeriodicTasks();
  }

  static bool get isRunning {
    return _collectTimer != null || _syncTimer != null;
  }
}
