import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:geotrack_frontend/services/auto_collect_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

class BackgroundManager {
  static final BackgroundManager _instance = BackgroundManager._internal();
  factory BackgroundManager() => _instance;
  BackgroundManager._internal();

  Timer? _collectTimer;
  Timer? _syncTimer;
  bool _isRunning = false;

  Future<void> start() async {
    if (_isRunning) {
      print('⚠️ Background manager already running');
      return;
    }

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        print('🚀 Starting background manager...');

        // Vérifier l'authentification
        final storageService = StorageService();
        final token = await storageService.getToken();

        if (token == null || token.isEmpty) {
          print('⚠️ Cannot start background manager: user not authenticated');
          return;
        }

        // Charger les intervalles
        final prefs = await SharedPreferences.getInstance();
        final collectInterval = prefs.getInt('collect_interval') ?? 5;
        final syncInterval = prefs.getInt('sync_interval') ?? 10;

        print(
          '⏰ Background intervals - Collect: ${collectInterval}min, Sync: ${syncInterval}min',
        );

        // Démarrer la collecte périodique
        _collectTimer = Timer.periodic(
          Duration(minutes: collectInterval),
          (timer) => _collectData(),
        );

        // Démarrer la synchronisation périodique
        _syncTimer = Timer.periodic(
          Duration(minutes: syncInterval),
          (timer) => _syncData(),
        );

        _isRunning = true;
        print('✅ Background manager started successfully');

        // Première collecte immédiate
        await _collectData();
        await _syncData();
      } catch (e) {
        print('❌ Error starting background manager: $e');
      }
    }
  }

  Future<void> _collectData() async {
    try {
      print('📍 Background: Collecting GPS data...');

      // Vérifier les permissions
      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) {
        print('⚠️ Location permission not granted for background collection');
        return;
      }

      await AutoCollectService.manualCollect();
      print('✅ Background collection completed');
    } catch (e) {
      print('❌ Background collection error: $e');
    }
  }

  Future<void> _syncData() async {
    try {
      print('🔄 Background: Syncing data...');

      // Vérifier la connexion internet
      final hasConnection = await _checkInternetConnection();
      if (!hasConnection) {
        print('⚠️ No internet connection for background sync');
        return;
      }

      // Vérifier l'authentification
      final storageService = StorageService();
      final token = await storageService.getToken();
      if (token == null || token.isEmpty) {
        print('⚠️ Cannot sync: user not authenticated');
        return;
      }

      await AutoCollectService.manualSync();
      print('✅ Background sync completed');
    } catch (e) {
      print('❌ Background sync error: $e');
    }
  }

  Future<bool> _checkLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (e) {
      print('❌ Error checking location permission: $e');
      return false;
    }
  }

  Future<bool> _checkInternetConnection() async {
    try {
      // Simple check - vous pouvez utiliser connectivity_plus si nécessaire
      // Pour l'instant, retourne true pour éviter les complications
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> stop() async {
    print('🛑 Stopping background manager...');

    _collectTimer?.cancel();
    _syncTimer?.cancel();
    _collectTimer = null;
    _syncTimer = null;
    _isRunning = false;

    print('✅ Background manager stopped');
  }

  bool get isRunning => _isRunning;
}
