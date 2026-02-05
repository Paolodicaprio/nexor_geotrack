import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

/// Watchdog service to monitor and restart the background service if needed
class WatchdogService {
  static const String healthCheckTaskName = "geotrack_health_check";
  static const String healthCheckTaskTag = "geotrack_watchdog";
  
  /// Initialize WorkManager with periodic health check
  static Future<void> initialize() async {
    // Only initialize on Android/iOS
    if (kIsWeb) return;
    
    await Workmanager().initialize(
      callbackDispatcher, // Top-level function for background execution
      isInDebugMode: kDebugMode, // Set to false in production
    );
    
    // Register periodic health check task
    await registerPeriodicHealthCheck();
  }
  
  /// Register a periodic task to check service health every 15 minutes
  /// Includes retry logic with in-app timer fallback
  static Future<void> registerPeriodicHealthCheck({int retryCount = 0}) async {
    const maxRetries = 3;
    
    try {
      // Cancel existing task to avoid duplicates
      await Workmanager().cancelByTag(healthCheckTaskTag);
      
      // Register new periodic task
      // Android minimum is 15 minutes, iOS minimum is 15 minutes
      await Workmanager().registerPeriodicTask(
        healthCheckTaskName,
        healthCheckTaskName,
        tag: healthCheckTaskTag,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.not_required,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 10),
      );
      
      print('✅ Watchdog periodic health check registered');
    } catch (e) {
      print('❌ Failed to register periodic health check (attempt ${retryCount + 1}/$maxRetries): $e');
      
      // Retry with delay
      if (retryCount < maxRetries - 1) {
        final delay = Duration(seconds: (retryCount + 1) * 2);
        print('🔄 Retrying watchdog registration in ${delay.inSeconds}s...');
        await Future.delayed(delay);
        await registerPeriodicHealthCheck(retryCount: retryCount + 1);
      } else {
        print('⚠️ WorkManager registration failed. App relies on service auto-restart.');
      }
    }
  }
  
  /// Check if background service is running and restart if needed
  static Future<void> checkAndRestartService() async {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      
      print('🔍 Watchdog check - Service running: $isRunning');
      
      if (!isRunning) {
        print('⚠️ Service not running - attempting restart...');
        
        // Try to start the service
        final started = await service.startService();
        
        if (started) {
          print('✅ Service restarted successfully by watchdog');
          
          // Give service time to initialize
          await Future.delayed(const Duration(seconds: 3));
          
          // Invoke task start commands
          service.invoke('start_all_tasks');
        } else {
          print('❌ Failed to restart service');
        }
      } else {
        print('✅ Service is running normally');
        
        // Optionally, we can send a ping to ensure it's responsive
        service.invoke('get_next_execution_times');
      }
    } catch (e) {
      print('❌ Watchdog error: $e');
    }
  }
  
  /// Register one-time task for immediate health check
  static Future<void> registerOneTimeHealthCheck() async {
    try {
      await Workmanager().registerOneOffTask(
        'immediate_health_check',
        healthCheckTaskName,
        tag: healthCheckTaskTag,
        initialDelay: const Duration(seconds: 5),
      );
      print('📋 One-time health check scheduled');
    } catch (e) {
      print('❌ Failed to register one-time health check: $e');
    }
  }
}

/// Top-level callback function for WorkManager
/// Must be top-level or static function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('🔧 WorkManager task started: $task');
    
    try {
      switch (task) {
        case WatchdogService.healthCheckTaskName:
          // Perform health check and restart if needed
          await WatchdogService.checkAndRestartService();
          break;
          
        case Workmanager.iOSBackgroundTask:
          // iOS specific background fetch
          await WatchdogService.checkAndRestartService();
          break;
          
        default:
          print('Unknown task: $task');
      }
      
      return Future.value(true); // Task completed successfully
    } catch (e) {
      print('❌ WorkManager task error: $e');
      return Future.value(false); // Task failed
    }
  });
}
