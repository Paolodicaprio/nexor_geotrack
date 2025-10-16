import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geotrack_frontend/services/storage_service.dart';

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

  // Méthode pour envoyer les données à l'UI
  void _sendTimersToUI(ServiceInstance service) {
    service.invoke('update_ui_timers',
      {
        'nextGpsTime': _nextGpsCollectionTime?.toIso8601String(),
        'nextSyncTime': _nextSyncTime?.toIso8601String(),
        'nextConfigSyncTime': _nextConfigSyncTime?.toIso8601String(),
      },
    );
  }

  // Collecte GPS
  Future<void> startGpsCollectTask(ServiceInstance service) async{
    final storage = StorageService();
    final config = await storage.getConfig();
    final duration = Duration(seconds: config.collectionInterval);

    // Définir la première exécution
    _nextGpsCollectionTime = DateTime.now().add(duration);
    _gpsCollectionTimer?.cancel();
    _sendTimersToUI(service); // Envoyer la mise à jour
    _gpsCollectionTimer = Timer.periodic(duration,(timer) async {
        await AutoCollectService.collectGpsDataBackground();

        _updateDashboardInfos(service);

        // Mettre à jour pour la prochaine exécution
        _nextGpsCollectionTime = DateTime.now().add(duration);
        _sendTimersToUI(service); // Envoyer la mise à jour
        print("collect task executed!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
          },
    );
    print("collect task called");
  }

  // Synchronisation des données GPS
  Future<void> startSyncTask(ServiceInstance service) async {
    final config = await StorageService().getConfig();
    final duration = Duration(seconds: config.sendInterval);
    _syncTimer?.cancel();

    _nextSyncTime = DateTime.now().add(duration);
    _sendTimersToUI(service);

    _syncTimer = Timer.periodic(duration, (timer) async {
      try{
        await AutoCollectService.syncGpsDataBackground();
      }catch(e){
        print("errror happened : $e");
        service.invoke("error_notification",{'error': e.toString()});
      }
        _updateDashboardInfos(service);

        _nextSyncTime = DateTime.now().add(duration);
        _sendTimersToUI(service);
        print("sync task executed!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
      },
    );
    print("sync task called");
  }

  // Synchronisation de la configuration
  Future<void> startConfigSyncTask(ServiceInstance service) async {
    final config = await StorageService().getConfig();
    final duration = Duration(minutes: config.configSyncInterval);
    _configSyncTimer?.cancel();

    _nextConfigSyncTime = DateTime.now().add(duration);
    _sendTimersToUI(service);
    _configSyncTimer = Timer.periodic(duration, (timer) async {
      try{
        await AutoCollectService.refetchConfig();
        restart(service);
      }catch(e){
        print("errror happened : $e");
        service.invoke("error_notification",{'error': e.toString()});
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
    // On passe 'service' à chaque méthode pour la communication
    startGpsCollectTask(service);
    startSyncTask(service);
    startConfigSyncTask(service);
  }

  Future<void> restartWithConfig(ServiceInstance service) async{
    print("config changedddddddddddd");
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

Future<void> initializeBackgroundService(bool withSyncTaks) async {
  final service = FlutterBackgroundService();

  if(await service.isRunning()){
    print("BG Service configure: already running.------------------");
    service.invoke("restart_tasks");

  }else{
    bool started = await service.startService();
    if (started){
      print("BG Service configure: service started.------------------");
      if(withSyncTaks){
        service.invoke("start_all_tasks");
      }else{
        await Future.delayed(Duration(seconds: 2));
          service.invoke("start_collect_task");
      }
    }else{
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
}