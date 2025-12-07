import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geotrack_frontend/services/background_service_manager.dart';
import 'package:http/http.dart' as http;
import 'package:geotrack_frontend/models/auth_model.dart';
import 'package:geotrack_frontend/utils/constants.dart';
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService with ChangeNotifier {
  bool _isAuthenticated = false;
  String? _token;
  int _failedAttempts = 0;
  DateTime? _blockUntil;
  String? _userEmail;

  bool get isAuthenticated => _isAuthenticated;
  String? get token => _token;
  int get failedAttempts => _failedAttempts;
  DateTime? get blockUntil => _blockUntil;
  String? get userEmail => _userEmail;

  // Méthodes de gestion du blocage
  bool isBlocked() {
    if (_blockUntil == null) return false;
    return DateTime.now().isBefore(_blockUntil!);
  }

  Duration getRemainingBlockTime() {
    if (_blockUntil == null) return Duration.zero;
    return _blockUntil!.difference(DateTime.now());
  }

  void setUserEmail(String email) {
    _userEmail = email;
    notifyListeners();
  }

  Future<String?> getEmail() async {
    // Essayer d'abord depuis userEmail
    if (_userEmail != null) {
      return _userEmail;
    }

    // Essayer depuis le token
    final emailFromToken = getEmailFromToken();
    if (emailFromToken != null) {
      _userEmail = emailFromToken;
      return _userEmail;
    }

    // Essayer depuis le stockage
    try {
      final storageService = StorageService();
      final storedEmail = await storageService.getUserEmail();
      if (storedEmail != null) {
        _userEmail = storedEmail;
        notifyListeners();
        return _userEmail;
      }
    } catch (e) {
      print('Error getting email from storage: $e');
    }

    return null;
  }

  // Dans auth_service.dart - méthode login
  Future<LoginResponse> login(String email, String accessCode) async {
    if (isBlocked()) {
      return LoginResponse(
        success: false,
        error:
            'Compte bloqué. Réessayez dans ${getRemainingBlockTime().inSeconds} secondes',
      );
    }

    try {
      // Charger l'URL personnalisée ou utiliser celle par défaut
      final storageService = StorageService();
      final customUrl = await storageService.getCustomUrl();
      final apiUrl = customUrl ?? Constants.apiBaseUrl;

      // Tester la connectivité
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return LoginResponse(
          success: false,
          error: 'Aucune connexion internet',
        );
      }

      // CORRECTION: L'API attend les paramètres dans la query string, pas dans le body
      // Construire l'URL avec les paramètres
      final uri = Uri.parse('$apiUrl/auth/login').replace(
        queryParameters: {
          'email': email.trim(),
          'access_code': accessCode.trim(),
        },
      );

      print('🔐 Login URL: $uri');

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            // CORRECTION: Envoyer un body vide puisque les paramètres sont dans l'URL
            body: json.encode({}),
          )
          .timeout(const Duration(seconds: 30));

      print('🔐 Login Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _token = data['access_token'];
        _isAuthenticated = true;
        _failedAttempts = 0;
        _blockUntil = null;
        _userEmail = email.trim();

        await storageService.saveToken(_token!);
        await storageService.saveUserEmail(email.trim());

        // Démarrer les services background après une connexion réussie
        // Désactivé temporairement pour éviter les crashs
        // await _startBackgroundServices();

        notifyListeners();
        return LoginResponse(success: true, token: _token);
      } else if (response.statusCode == 401) {
        _handleFailedAttempt();
        return LoginResponse(
          success: false,
          error:
              'Email ou code d\'accès incorrect. Tentatives restantes: ${3 - _failedAttempts}',
        );
      } else if (response.statusCode == 422) {
        // Erreur de validation
        final errorData = json.decode(response.body);
        String errorMessage = 'Données invalides';

        if (errorData['detail'] is String) {
          errorMessage = errorData['detail'];
        } else if (errorData['detail'] is List &&
            errorData['detail'].isNotEmpty) {
          // Prendre le premier message d'erreur
          errorMessage = errorData['detail'][0]['msg'] ?? errorMessage;
        }

        return LoginResponse(success: false, error: errorMessage);
      } else {
        final errorData = json.decode(response.body);
        String errorMessage = 'Erreur de connexion';

        if (errorData['detail'] is String) {
          errorMessage = errorData['detail'];
        } else if (errorData['detail'] is List &&
            errorData['detail'].isNotEmpty) {
          errorMessage = errorData['detail'][0]['msg'];
        }

        return LoginResponse(success: false, error: errorMessage);
      }
    } on SocketException {
      return LoginResponse(
        success: false,
        error: 'Impossible de se connecter au serveur',
      );
    } on TimeoutException {
      return LoginResponse(success: false, error: 'Timeout de connexion');
    } catch (e) {
      print('❌ Login error: $e');
      return LoginResponse(success: false, error: 'Erreur de connexion: $e');
    }
  }

  void _handleFailedAttempt() {
    _failedAttempts++;

    if (_failedAttempts >= 3) {
      _blockUntil = DateTime.now().add(const Duration(seconds: 30));
    }

    notifyListeners();
  }

  Future<void> logout() async {
    _isAuthenticated = false;
    _token = null;
    _failedAttempts = 0;
    _blockUntil = null;
    _userEmail = null;

    final storageService = StorageService();
    await storageService.deleteToken();
    await storageService.deleteUserEmail();

    // Arrêter les services background lors de la déconnexion
    await _stopBackgroundServices();

    notifyListeners();
  }

  Future<bool> checkAuth() async {
    final storageService = StorageService();
    final token = await storageService.getToken();
    final email = await storageService.getUserEmail();

    if (token != null) {
      _token = token;
      _isAuthenticated = true;
      _userEmail = email;
      notifyListeners();
      return true;
    }

    _isAuthenticated = false;
    _token = null;
    _userEmail = null;
    return false;
  }

  String? getEmailFromToken() {
    if (_token == null) return null;
    try {
      final parts = _token!.split('.');
      if (parts.length != 3) return null;

      final payload = parts[1];
      // Padding pour base64Url
      final padded = payload.padRight((payload.length + 3) & ~3, '=');
      final normalized = base64Url.normalize(padded);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final payloadMap = json.decode(decoded);

      return payloadMap['sub']; // L'email est dans le claim "sub"
    } catch (e) {
      print('Error decoding token: $e');
      return null;
    }
  }

  // Méthodes pour gérer les services background - SIMPLIFIÉES
  Future<void> _startBackgroundServices() async {
    try {
      await BackgroundServiceManager.startService();
    } catch (e) {
      print('⚠️ Erreur lors du démarrage des services background: $e');
    }
  }

  // Remplacer _stopBackgroundServices() par:
  Future<void> _stopBackgroundServices() async {
    try {
      await BackgroundServiceManager.stopService();
    } catch (e) {
      print('⚠️ Erreur lors de l\'arrêt des services background: $e');
    }
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
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
  static Future<void> _onBackgroundServiceStart(ServiceInstance service) async {
    print('🔄 Service background démarré');

    // Configurer la notification pour Android
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "GeoTrack Service",
        content: "Collecte GPS active",
      );
    }

    // Démarrer un timer simple pour montrer que le service fonctionne
    Timer.periodic(const Duration(minutes: 1), (timer) async {
      print('⏰ Service background actif - tick');

      // Mettre à jour la notification
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: "GeoTrack Service",
          content: "Actif - ${DateTime.now().toString().substring(11, 16)}",
        );
      }
    });
  }

  // Méthode pour démarrer manuellement les services (à utiliser depuis l'UI)
  Future<void> startBackgroundServicesManually() async {
    await _startBackgroundServices();
  }

  // Méthode pour arrêter manuellement les services (à utiliser depuis l'UI)
  Future<void> stopBackgroundServicesManually() async {
    await _stopBackgroundServices();
  }
}

// Fonction d'inscription externe (à garder séparée du service)
Future<Map<String, dynamic>> register(String email) async {
  try {
    final storageService = StorageService();
    final customUrl = await storageService.getCustomUrl();
    final apiUrl = customUrl ?? Constants.apiBaseUrl;

    // CORRECTION: L'API attend un body JSON avec l'email
    final response = await http
        .post(
          Uri.parse('$apiUrl/auth/register'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: json.encode({'email': email.trim()}),
        )
        .timeout(const Duration(seconds: 30));

    print('📝 Register response: ${response.statusCode} - ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return {
        'success': true,
        'message':
            'Compte créé avec succès! Code d\'accès: ${data['access_code']}',
        'access_code': data['access_code'],
        'email': data['email'],
      };
    } else {
      final errorData = json.decode(response.body);
      String errorMessage = 'Erreur lors de l\'inscription';

      if (errorData['detail'] is String) {
        errorMessage = errorData['detail'];
      } else if (errorData['detail'] is List &&
          errorData['detail'].isNotEmpty) {
        errorMessage = errorData['detail'][0]['msg'];
      }

      return {'success': false, 'message': errorMessage};
    }
  } on SocketException {
    return {
      'success': false,
      'message': 'Impossible de se connecter au serveur',
    };
  } on TimeoutException {
    return {'success': false, 'message': 'Timeout de connexion'};
  } catch (e) {
    print('❌ Register error: $e');
    return {'success': false, 'message': 'Erreur de connexion: $e'};
  }
}
