import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geotrack_frontend/models/auth_model.dart';
import 'package:geotrack_frontend/utils/constants.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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

  Future<LoginResponse> login(String email, String accessCode) async {
    if (isBlocked()) {
      return LoginResponse(
        success: false,
        error:
            'Compte bloqué. Réessayez dans ${getRemainingBlockTime().inSeconds} secondes',
      );
    }

    try {
      final apiUrl = await _getApiUrl();

      // Test de connectivité
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return LoginResponse(
          success: false,
          error: 'Aucune connexion internet',
        );
      }

      // Utiliser les paramètres query comme spécifié dans l'API
      final uri = Uri.parse(
        '$apiUrl/auth/login',
      ).replace(queryParameters: {'email': email, 'access_code': accessCode});

      final response = await http
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _token = data['access_token'];
        _isAuthenticated = true;
        _failedAttempts = 0;
        _blockUntil = null;
        _userEmail = email;

        await StorageService().saveToken(_token!);
        await StorageService().saveUserEmail(email);
        notifyListeners();

        return LoginResponse(success: true, token: _token);
      } else if (response.statusCode == 401) {
        _handleFailedAttempt();
        return LoginResponse(
          success: false,
          error:
              'Code d\'accès incorrect. Tentatives restantes: ${3 - _failedAttempts}',
        );
      } else {
        final errorData = json.decode(response.body);
        return LoginResponse(
          success: false,
          error: errorData['detail'] ?? 'Erreur de connexion',
        );
      }
    } on SocketException {
      return LoginResponse(
        success: false,
        error: 'Impossible de se connecter au serveur',
      );
    } on TimeoutException {
      return LoginResponse(success: false, error: 'Timeout de connexion');
    } catch (e) {
      return LoginResponse(success: false, error: 'Erreur de connexion: $e');
    }
  }

  // AJOUT: Méthode register dans la classe AuthService
  Future<Map<String, dynamic>> register(String email) async {
    try {
      // Test avec une requête GET simple d'abord
      print('🔍 Testing basic connectivity...');
      final testResponse = await http.get(
        Uri.parse('https://portal.inma.ucl.ac.be'),
        headers: {'User-Agent': 'Flutter App'},
      );
      print('🌐 Basic connectivity test: ${testResponse.statusCode}');

      // Maintenant la requête POST
      final apiUrl = 'https://portal.inma.ucl.ac.be/geotrack/auth/register';
      print('🔄 Register attempt - URL: $apiUrl');

      final response = await http
          .post(
            Uri.parse(apiUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': 'Flutter App',
            },
            body: json.encode({'email': email}),
          )
          .timeout(const Duration(seconds: 10));

      print('📤 Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': 'Compte créé avec succès',
          'access_code': data['access_code'],
        };
      } else {
        return {
          'success': false,
          'message': 'Erreur HTTP ${response.statusCode}: ${response.body}',
        };
      }
    } catch (e) {
      print('❌ Detailed error: $e');
      print('❌ Error type: ${e.runtimeType}');
      print('❌ Stack trace: ${StackTrace.current}');

      return {'success': false, 'message': 'Erreur détaillée: ${e.toString()}'};
    }
  }

  void _handleFailedAttempt() {
    _failedAttempts++;

    if (_failedAttempts >= 3) {
      _blockUntil = DateTime.now().add(const Duration(seconds: 30));
    }

    notifyListeners();
  }

  bool isBlocked() {
    if (_blockUntil == null) return false;
    return DateTime.now().isBefore(_blockUntil!);
  }

  Duration getRemainingBlockTime() {
    if (_blockUntil == null) return Duration.zero;
    return _blockUntil!.difference(DateTime.now());
  }

  Future<void> logout() async {
    _isAuthenticated = false;
    _token = null;
    _failedAttempts = 0;
    _blockUntil = null;
    _userEmail = null;
    await StorageService().deleteToken();
    await StorageService().deleteUserEmail();
    notifyListeners();
  }

  Future<bool> checkAuth() async {
    final token = await StorageService().getToken();
    final email = await StorageService().getUserEmail();

    if (token != null && email != null) {
      _token = token;
      _userEmail = email;
      _isAuthenticated = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> forgotPin(String email) async {
    try {
      final apiUrl = await _getApiUrl();

      final response = await http.post(
        Uri.parse(
          '$apiUrl/auth/register',
        ), // Réutiliser register pour générer un nouveau code
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': 'Nouveau code d\'accès envoyé par email',
          'access_code': data['access_code'],
        };
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'message': errorData['detail'] ?? 'Erreur lors de la récupération',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Erreur de connexion: $e'};
    }
  }

  void setUserEmail(String email) {
    _userEmail = email;
    StorageService().saveUserEmail(email);
    notifyListeners();
  }

  Future<String> _getApiUrl() async {
    final customUrl = await StorageService().getCustomUrl();
    if (customUrl != null && customUrl.isNotEmpty) {
      return customUrl;
    }
    return dotenv.get('API_BASE_URL', fallback: Constants.apiBaseUrl);
  }
}

Future<Map<String, dynamic>> registerUser(String email) async {
  final authService = AuthService();
  return await authService.register(email);
}
