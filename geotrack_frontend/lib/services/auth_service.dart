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
import 'dart:convert';

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
          .post(
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

  Future<Map<String, dynamic>> register(String email) async {
    try {
      final apiUrl = await _getApiUrl();

      print('🔄 Register attempt - URL: $apiUrl/auth/register');

      final response = await http
          .post(
            Uri.parse('$apiUrl/auth/register'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({'email': email}),
          )
          .timeout(const Duration(seconds: 10));

      print('📤 Response Status: ${response.statusCode}');
      print('📤 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': 'Compte créé avec succès',
          'access_code': data['access_code'],
        };
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'message':
              errorData['detail'] ?? 'Erreur HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ Detailed error: $e');
      return {
        'success': false,
        'message': 'Erreur de connexion: ${e.toString()}',
      };
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
    final store = StorageService();
    await store.deleteUserEmail();
    await store.clearAllData();
    notifyListeners();
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

  Future<bool> checkAuth() async {
    try {
      final token = await StorageService().getToken();
      final email = await StorageService().getUserEmail();

      print(
        '🔐 Checking auth - Token: ${token != null ? "exists" : "null"}, Email: $email',
      );

      if (token == null || token.isEmpty || email == null || email.isEmpty) {
        print('❌ Auth failed: Token or email missing');
        _isAuthenticated = false;
        _token = null;
        _userEmail = null;
        notifyListeners();
        return false;
      }

      // Vérifier si le token est valide
      if (!await _isTokenValid(token)) {
        print('❌ Token expired or invalid');
        await logout(); // Nettoyer les données expirées
        return false;
      }

      // Token valide - restaurer la session
      _token = token;
      _userEmail = email;
      _isAuthenticated = true;

      print('✅ Auth successful - User: $email');
      notifyListeners();
      return true;
    } catch (e) {
      print('❌ Error in checkAuth: $e');
      await logout(); // Nettoyer en cas d'erreur
      return false;
    }
  }

  Future<bool> _isTokenValid(String token) async {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        print('❌ Invalid token format');
        return false;
      }

      // Decoder le payload JWT (base64Url)
      final payload = parts[1];
      // Ajouter le padding manquant si nécessaire
      String paddedPayload = payload.padRight((payload.length + 3) & ~3, '=');

      final decoded = utf8.decode(base64Url.decode(paddedPayload));
      final payloadMap = json.decode(decoded);

      final exp = payloadMap['exp'] as int?;
      if (exp == null) {
        print('✅ Token has no expiration date');
        return true; // Si pas d'expiration, considérer valide
      }

      final expiryTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      final isValid = DateTime.now().isBefore(expiryTime);

      print('📅 Token expiry: $expiryTime, Valid: $isValid');
      return isValid;
    } catch (e) {
      print('❌ Error validating token: $e');
      return false;
    }
  }
}
