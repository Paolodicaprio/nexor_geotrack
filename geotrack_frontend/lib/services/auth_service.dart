import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geotrack_frontend/main.dart';
import 'package:geotrack_frontend/services/background_manager.dart';
import 'package:http/http.dart' as http;
import 'package:geotrack_frontend/models/auth_model.dart';
import 'package:geotrack_frontend/utils/constants.dart';
import 'storage_service.dart';

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

  // Méthodes manquantes ajoutées
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

      // Construire l'URL avec les paramètres QUERY
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

        // Démarrer le background manager après connexion réussie
        try {
          // Attendre un peu pour que l'interface soit stable
          await Future.delayed(const Duration(seconds: 1));
          await BackgroundManager().start();
        } catch (e) {
          print('⚠️ Failed to start background manager: $e');
        }

        notifyListeners();
        return LoginResponse(success: true, token: _token);
      } else if (response.statusCode == 401) {
        _handleFailedAttempt();
        return LoginResponse(
          success: false,
          error:
              'Email ou code d\'accès incorrect. Tentatives restantes: ${3 - _failedAttempts}',
        );
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

    // Note: stopBackgroundService doit être appelé depuis le widget
    // car c'est une fonction dans main.dart
    await StorageService().deleteToken();
    notifyListeners();
  }

  Future<bool> checkAuth() async {
    final token = await StorageService().getToken();
    if (token != null) {
      _token = token;
      _isAuthenticated = true;
      notifyListeners();
      return true;
    }
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
}

// Fonction d'inscription externe (à garder séparée du service)
// Fonction d'inscription externe (à garder séparée du service)
Future<Map<String, dynamic>> register(String email) async {
  try {
    final storageService = StorageService();
    final customUrl = await storageService.getCustomUrl();
    final apiUrl = customUrl ?? Constants.apiBaseUrl;

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
