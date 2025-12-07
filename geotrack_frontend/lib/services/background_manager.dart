import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:geotrack_frontend/services/auto_collect_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geotrack_frontend/services/api_service.dart';

class BackgroundManager {
  static final BackgroundManager _instance = BackgroundManager._internal();
  factory BackgroundManager() => _instance;
  BackgroundManager._internal();

  Timer? _collectTimer;
  Timer? _syncTimer;
  bool _isRunning = false;

  Future<bool> _checkAuthentication() async {
    try {
      final storageService = StorageService();
      final token = await storageService.getToken();

      if (token == null || token.isEmpty) {
        print('⚠️ Background: Utilisateur non authentifié');
        return false;
      }

      // Vérifier la validité du token en faisant une requête simple
      final apiService = ApiService();
      await apiService.getConfig();
      return true;
    } catch (e) {
      print('❌ Background: Authentication check failed: $e');
      return false;
    }
  }

  Future<void> start() async {
    if (_isRunning) {
      print('⚠️ Background manager déjà en cours d\'exécution');
      return;
    }

    if (!kIsWeb) {
      try {
        print('🚀 Démarrage du background manager...');

        // Vérifier l'authentification
        final isAuthenticated = await _checkAuthentication();
        if (!isAuthenticated) {
          print('⚠️ Impossible de démarrer: utilisateur non authentifié');
          return;
        }

        final prefs = await SharedPreferences.getInstance();
        final collectInterval = prefs.getInt('collect_interval') ?? 5;
        final syncInterval = prefs.getInt('sync_interval') ?? 10;

        print(
          '⏰ Intervalles - Collecte: ${collectInterval}min, Sync: ${syncInterval}min',
        );

        // Annuler les timers existants
        _collectTimer?.cancel();
        _syncTimer?.cancel();

        // Démarrer les timers
        _collectTimer = Timer.periodic(
          Duration(minutes: collectInterval),
          (timer) => _collectData(),
        );

        _syncTimer = Timer.periodic(
          Duration(minutes: syncInterval),
          (timer) => _syncData(),
        );

        _isRunning = true;
        print('✅ Background manager démarré avec succès');

        // Exécuter immédiatement une première collecte et synchronisation
        await _collectData();
        await _syncData();
      } catch (e) {
        print('❌ Erreur de démarrage du background manager: $e');
      }
    }
  }

  Future<void> _collectData() async {
    try {
      print('📍 Background: Collecte de données GPS...');

      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) {
        print(
          '⚠️ Permission de localisation non accordée pour la collecte en arrière-plan',
        );
        return;
      }

      // Vérifier l'authentification avant chaque collecte
      final isAuthenticated = await _checkAuthentication();
      if (!isAuthenticated) {
        print('⚠️ Collecte annulée: utilisateur non authentifié');
        return;
      }

      await AutoCollectService.manualCollect();
      print('✅ Collecte en arrière-plan terminée');
    } catch (e) {
      print('❌ Erreur de collecte en arrière-plan: $e');
    }
  }

  Future<void> _syncData() async {
    try {
      print('🔄 Background: Synchronisation des données...');

      // Vérifier l'authentification avant chaque synchronisation
      final isAuthenticated = await _checkAuthentication();
      if (!isAuthenticated) {
        print('⚠️ Synchronisation annulée: utilisateur non authentifié');
        return;
      }

      await AutoCollectService.manualSync();
      print('✅ Synchronisation en arrière-plan terminée');
    } catch (e) {
      print('❌ Erreur de synchronisation en arrière-plan: $e');
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
      print('❌ Erreur vérification permission localisation: $e');
      return false;
    }
  }

  Future<void> stop() async {
    print('🛑 Arrêt du background manager...');

    _collectTimer?.cancel();
    _syncTimer?.cancel();
    _collectTimer = null;
    _syncTimer = null;
    _isRunning = false;

    print('✅ Background manager arrêté');
  }

  // Méthode pour mettre à jour les intervalles
  Future<void> updateIntervals() async {
    if (_isRunning) {
      print('🔄 Mise à jour des intervalles du background manager...');
      await stop();
      await Future.delayed(const Duration(seconds: 1));
      await start();
    }
  }

  bool get isRunning => _isRunning;
}
