import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geotrack_frontend/services/auth_service.dart';
import 'package:geotrack_frontend/services/safe_http.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/gps_data_model.dart';
import 'auto_collect_service.dart';
import 'notification_service.dart';


class BackgroundTaskManager {
  Timer? _gpsCollectionTimer;
  Timer? _syncTimer;
  Timer? _configSyncTimer;

  // Stocker les prochaines heures d'exécution
  DateTime? _nextGpsCollectionTime;
  DateTime? _nextSyncTime;
  DateTime? _nextConfigSyncTime;


  //verrou des taches
  bool _isCollectTaskRunning = false;
  bool _isSyncedTaskRunning = false;
  bool _isConfigSyncTaskRunning = false;

  // Méthode pour envoyer les données à l'UI
  void _sendTimersToUI(ServiceInstance service) {
    service.invoke('update_ui_timers',
      {
        'nextGpsTime': _nextGpsCollectionTime?.toIso8601String(),
        'nextSyncTime': _nextSyncTime?.toIso8601String(),
        'nextConfigSyncTime': _nextConfigSyncTime?.toIso8601String(),
      },
    );
    
    // Persist timer states whenever they're updated
    _persistTimerStates();
  }
  
  // Save timer states to persistent storage
  Future<void> _persistTimerStates() async {
    await StorageService().saveTimerStates(
      nextGpsTime: _nextGpsCollectionTime,
      nextSyncTime: _nextSyncTime,
      nextConfigTime: _nextConfigSyncTime,
    );
  }
  
  // Restore timer states from persistent storage
  Future<void> _restoreTimerStates() async {
    final states = await StorageService().getTimerStates();
    final now = DateTime.now();
    
    // Only restore if timers are in the future
    if (states['gps'] != null && states['gps']!.isAfter(now)) {
      _nextGpsCollectionTime = states['gps'];
    }
    if (states['sync'] != null && states['sync']!.isAfter(now)) {
      _nextSyncTime = states['sync'];
    }
    if (states['config'] != null && states['config']!.isAfter(now)) {
      _nextConfigSyncTime = states['config'];
    }
  }

  // Collecte GPS
  Future<void> startGpsCollectTask(ServiceInstance service) async {
    // Skip if already running
    if (_gpsCollectionTimer != null && _gpsCollectionTimer!.isActive) {
      print("⚠️ GPS collection task already running - skipping");
      return;
    }
    
    final storage = StorageService();
    final config = await storage.getConfig();
    final duration = Duration(seconds: config.collectionInterval);

    // Définir la prochaine exécution
    _nextGpsCollectionTime = DateTime.now().add(duration);
    _gpsCollectionTimer?.cancel();
    _sendTimersToUI(service); // Envoyer la mise à jour

    _gpsCollectionTimer = Timer.periodic(duration, (timer) async {
      if (_isCollectTaskRunning) {
        _nextGpsCollectionTime = DateTime.now().add(duration);
        _sendTimersToUI(service);
        return;
      }
      _isCollectTaskRunning = true;
      try {
        await AutoCollectService.collectGpsDataBackground();
        _updateDashboardInfos(service);
        // Mettre à jour pour la prochaine exécution
        _nextGpsCollectionTime = DateTime.now().add(duration);
        _sendTimersToUI(service); // Envoyer la mise à jour
      } catch (e) {
        print("erreur inattendue dans le timer de collecte gps: $e");
      } finally {
        _isCollectTaskRunning = false;
        print("collect task executed!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
      }
    });
    print("collect task called");
  }

  // Synchronisation des données GPS
  Future<void> startSyncTask(ServiceInstance service) async {
    // Skip if already running
    if (_syncTimer != null && _syncTimer!.isActive) {
      print("⚠️ Sync task already running - skipping");
      return;
    }
    
    final config = await StorageService().getConfig();
    final duration = Duration(seconds: config.sendInterval);
    _syncTimer?.cancel();

    _nextSyncTime = DateTime.now().add(duration);
    _sendTimersToUI(service);

    _syncTimer = Timer.periodic(duration, (timer) async {
      if(_isSyncedTaskRunning){
        return; // Skip this cycle
      }
      
      _isSyncedTaskRunning = true;
      
      try {
        await AutoCollectService.syncGpsDataBackground();
        
        // Update only on success
        _nextSyncTime = DateTime.now().add(duration);
        _sendTimersToUI(service);
        _updateDashboardInfos(service);
        
      } catch(e) {
        print("Error happened: $e");
        
        if (e is CustomHttpException && e.statusCode == 401) {
          final loginResponse = await AuthService.tryReconnectUser();
          if(loginResponse.success) {
            try {
              await AutoCollectService.syncGpsDataBackground(retry: true);
              // Update on retry success
              _nextSyncTime = DateTime.now().add(duration);
              _sendTimersToUI(service);
              _updateDashboardInfos(service);
            } catch(retryError) {
              print("Retry failed: $retryError");
            }
          }
        }
        
        service.invoke("error_notification", {'error': e.toString()});
        
      } finally {
        _isSyncedTaskRunning = false;
        
        // Always set next execution time
        if (_nextSyncTime == null || DateTime.now().isAfter(_nextSyncTime!)) {
          _nextSyncTime = DateTime.now().add(duration);
          _sendTimersToUI(service);
        }
      }
      
      print("sync task executed!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
    },
    );
    print("sync task called");
  }

  // Synchronisation de la configuration
  Future<void> startConfigSyncTask(ServiceInstance service) async {
    // Skip if already running
    if (_configSyncTimer != null && _configSyncTimer!.isActive) {
      print("⚠️ Config sync task already running - skipping");
      return;
    }
    
    final config = await StorageService().getConfig();
    final duration = Duration(minutes: config.configSyncInterval);
    _configSyncTimer?.cancel();

    _nextConfigSyncTime = DateTime.now().add(duration);
    _sendTimersToUI(service);
    _configSyncTimer = Timer.periodic(duration, (timer) async {
      if(_isConfigSyncTaskRunning){
        _nextConfigSyncTime = DateTime.now().add(duration);
        _sendTimersToUI(service);
        return;
      }
      _isConfigSyncTaskRunning=true;
      try{
        await AutoCollectService.refetchConfig();
        restart(service);

      }catch(e){
        // on essaie de se reconnecter si c'est une erreur 401
        if (e is CustomHttpException && e.statusCode == 401){
          final loginResponse = await AuthService.tryReconnectUser();
          if(loginResponse.success){
           await AutoCollectService.refetchConfig(retry: true);
           restart(service);
          }
        }
        print("errror happened : $e");
        service.invoke("error_notification",{'error': e.toString()});
      }finally{
        _isConfigSyncTaskRunning=false;
      }
        _updateDashboardInfos(service);
        _nextConfigSyncTime = DateTime.now().add(duration);
        _sendTimersToUI(service);
        print("config sync task executed!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
      },
    );
    print("config sync task called");
  }

  Future<void> startPeriodicTasks(ServiceInstance service) async {
    // Restore timer states from persistent storage
    await _restoreTimerStates();
    
    // On passe 'service' à chaque méthode pour la communication
    await startGpsCollectTask(service);
    await startSyncTask(service);
    await startConfigSyncTask(service);
    
    print('✅ All periodic tasks started successfully');
  }

  Future<void> restartWithConfig(ServiceInstance service) async{
    StorageService().reloadStorage();
    restart(service);
  }

  // mettre a jour les infos affiché sur le dashboard
  Future<void> _updateDashboardInfos(ServiceInstance service) async{
        final storage = StorageService();
        final pendingData = await storage.getPendingGpsData();
        final lastCollection = await storage.getLastCollectionTime();
        final syncedData = await storage.getSyncedGpsData();
        final  stats = {
          'pending_count': pendingData.length,
          'last_collection': lastCollection?.toIso8601String()
        };

        final pendingWithStatus =
        pendingData.map((data) => data.copyWith(synced: false)).toList();
        final syncedWithStatus =
        syncedData.map((data) => data.copyWith(synced: true)).toList();

        // Combiner toutes les données et trier par timestamp
        final List<GpsData> allData = [...pendingWithStatus, ...syncedWithStatus];
        allData.sort((a, b) => b.timestamp.compareTo(a.timestamp));


        service.invoke('data_updated', {
          'task': 'gps_collect_done',
          'pendingData':pendingData,
          'stats':stats,
          'allData':allData
        });
  }

  void stopAllTasks() {
    _gpsCollectionTimer?.cancel();
    _syncTimer?.cancel();
    _configSyncTimer?.cancel();
    _gpsCollectionTimer = null;
    _syncTimer = null;
    _configSyncTimer = null;
    _nextGpsCollectionTime = null;
    _nextSyncTime = null;
    _nextConfigSyncTime = null;
  }

  Future<void> restart(ServiceInstance service) async {
    stopAllTasks();
    await startPeriodicTasks(service);
  }
}
final BackgroundTaskManager taskManager = BackgroundTaskManager();

Future<void> initializeBackgroundService(bool withSyncTasks) async {
  final service = FlutterBackgroundService();

  if (await service.isRunning()) {
    print("BG Service configure: already running.------------------");
    // Service already running (likely from boot auto-start)
    // Just request current state to update UI
    service.invoke("get_next_execution_times");
    service.invoke("get_dashboard_infos");
    
    // If user just logged in and sync tasks weren't running, start them now
    if (withSyncTasks) {
      service.invoke("start_sync_task");
      service.invoke("start_config_sync_task");
    }
  } else {
    bool started = await service.startService();
    if (started) {
      print("BG Service configure: service started.------------------");
      // Tasks will auto-start in onStart via _autoStartTasksOnBoot
      // Just wait and update UI
      await Future.delayed(Duration(seconds: 4));
      service.invoke("get_next_execution_times");
      service.invoke("get_dashboard_infos");
    } else {
      print("BG Service configure: service not started.------------------");
    }
  }
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
    taskManager.stopAllTasks();
    NotificationService.showPersistentNotification(
      title: "GeoTrack Service",
      content: "GPS collection service stopped",
    );
    service.stopSelf();
  });

  // Ensuite  charger  .env
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    print("Erreur lors du chargement de .env: $e");
  }

/*  Hive.initFlutter();
  Hive.registerAdapter(GpsDataAdapter());
  await Hive.openBox<GpsData>('peopleBox');*/

  // cas de demande manuelle depuis l'ui
  service.on('get_next_execution_times').listen((event) {
    taskManager._sendTimersToUI(service);
  });

  service.on('get_dashboard_infos').listen((event) {
    taskManager._updateDashboardInfos(service);
  });

  service.on('start_collect_task').listen((event) async{
    await taskManager.startGpsCollectTask(service);
  });
  service.on('start_sync_task').listen((event) async{
    await taskManager.startSyncTask(service);
  });

  service.on('start_config_sync_task').listen((event) async{
    await taskManager.startConfigSyncTask(service);
  });
  service.on('start_all_tasks').listen((event) async{
    await taskManager.startPeriodicTasks(service);
  });

  service.on('restart_tasks').listen((event) async {
    await taskManager.restart(service);
  });

  service.on('config_changed').listen((event)async{
    await taskManager.restartWithConfig(service);
  });

  // AUTO-START TASKS ON BOOT/RESTART
  // Check if user was previously authenticated and auto-start tasks
  await _autoStartTasksOnBoot(service);
}

/// Auto-start tasks when service starts (e.g., after device boot)
/// If user was previously authenticated (has stored token), start all tasks including sync
/// Otherwise, only start GPS collection
Future<void> _autoStartTasksOnBoot(ServiceInstance service) async {
  print("🚀 Auto-starting tasks on boot...");
  
  try {
    final storage = StorageService();
    final token = await storage.getToken();
    final hasStoredCredentials = token != null && token.isNotEmpty;
    
    // Small delay to ensure service is fully initialized
    await Future.delayed(Duration(seconds: 2));
    
    // Always start GPS collection
    await taskManager.startGpsCollectTask(service);
    print("✅ GPS collection task auto-started");
    
    // Start sync tasks only if user was previously authenticated
    if (hasStoredCredentials) {
      print("🔐 Found stored credentials - starting sync tasks");
      await taskManager.startSyncTask(service);
      await taskManager.startConfigSyncTask(service);
      print("✅ Sync and config sync tasks auto-started");
    } else {
      print("⚠️ No stored credentials - sync tasks will start after login");
    }
  } catch (e) {
    print("❌ Error auto-starting tasks: $e");
  }
}