import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geotrack_frontend/services/api_service.dart';
import 'package:geotrack_frontend/services/safe_http.dart';
import 'package:http/http.dart' as http;
import 'package:geotrack_frontend/models/auth_model.dart';
import 'package:geotrack_frontend/utils/constants.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'storage_service.dart';
import 'dart:convert';

class AuthService with ChangeNotifier {
  bool _isAuthenticated = false;
  String? _token;
  String? _userEmail;

  bool get isAuthenticated => _isAuthenticated;
  String? get token => _token;
  String? get userEmail => _userEmail;
  bool get hasToken => _token!=null && _token!.isNotEmpty;

  Future<LoginResponse> login(String username, String password) async {
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
        '$apiUrl/web/session/authenticate');
      final body =
        {
          "jsonrpc": "2.0",
          "params": {
            "db": await StorageService().getDatabaseName(),
            "login": username,
            "password": password
          }
        };

      final response = await SafeHttp.request(()=>http
          .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: json.encode(body)
      )
          .timeout(const Duration(seconds: 40)));
      print("------------------------------------------");
      print(response.body);
      print(response.statusCode);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // verifier que la connexion a marché
        if (data["result"]!=null && data["result"]["partner_id"]!=null) {
          final rawCookie = response.headers['set-cookie'];
          if (rawCookie != null) {
            print("Cookie reçu : $rawCookie");

            _token = rawCookie;
            _isAuthenticated = true;
            _userEmail = username;

            await StorageService().saveToken(_token!);
            await StorageService().saveUserUsername(username);
            await StorageService().savePassword(password);
            notifyListeners();

            return LoginResponse(success: true, token: _token);
          }else{
            return LoginResponse(
              success: false,
              error: 'Connection failed: Cookie not found',
            );
          }
        }
        print('reponse apres login : ${response.body}  - ${response.statusCode}');
        return LoginResponse(
          success: false,
          error: 'Connection failed : Invalid credentials',
        );
      } else if (response.statusCode == 401) {
        return LoginResponse(
          success: false,
          error:
              'Invalid credentials',
        );
      } else {
        final errorData = json.decode(response.body);
        return LoginResponse(
          success: false,
          error: errorData['detail'] ?? 'Connection Failed',
        );
      }
    } on SocketException {
      return LoginResponse(
        success: false,
        error: 'Unable to connect to the server',
      );
    } on TimeoutException {
      return LoginResponse(success: false, error: 'Connection timeout');
    } catch (e) {
      String message;
      if(e.toString().contains("HandshakeException")){
        message = "Unable to connect to the server, check the API URL";
      }else{
        message = e.toString();
      }
      return LoginResponse(success: false, error: 'Connection failed: $message');
    }
  }


  /// Logout user from UI but KEEP credentials for auto-reconnect
  /// This is critical for MDM deployments where the app must self-heal
  /// after session expiry even if user manually logged out
  Future<void> logout() async {
    _isAuthenticated = false;
    // Keep _token - needed for current session requests
    _userEmail = null;
    // DO NOT delete credentials - they are needed for auto-reconnect
    // when session expires (401/303). This ensures the background
    // sync can always recover without manual intervention.
    // 
    // Credentials are only fully cleared when:
    // - User changes API URL (different server)
    // - User explicitly requests full data wipe
    notifyListeners();
  }

  void setUserEmail(String email) {
    _userEmail = email;
    StorageService().saveUserUsername(email);
    notifyListeners();
  }

  Future<String> _getApiUrl() async {
    final customUrl = await StorageService().getCustomUrl();
    return customUrl;
  }

  Future<bool> checkAuth() async {
    try {
      final token = await StorageService().getToken();
      final username = await StorageService().getUserUsername();

      print(
        '🔐 Checking auth - Token: ${token != null ? "exists" : "null"},Username: $username',
      );

      if (token == null || token.isEmpty || username == null || username.isEmpty) {
        print('❌ Auth failed: Token or email missing');
        _isAuthenticated = false;
        // _token = null;
        _userEmail = null;
        notifyListeners();
        return false;
      }

      // Vérifier si le token est valide
      // if (!await _isTokenValid(token)) {
      //   print('❌ Token expired or invalid');
      //   await logout(); // Nettoyer les données expirées
      //   return false;
      // }

      // Token valide - restaurer la session
      _token = token;
      _userEmail = username;
      _isAuthenticated = true;

      print('✅ Auth successful - User: $username');
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

  static Future<LoginResponse> tryReconnectUser()async{
    final storage = StorageService();
    try {
      // Check credentials exist before attempting reconnection
      final username = await storage.getUserUsername();
      final password = await storage.getPassword();
      
      if (username == null || username.isEmpty || 
          password == null || password.isEmpty) {
        print('❌ Cannot reconnect: Missing credentials (username: ${username != null ? "exists" : "null"}, password: ${password != null ? "exists" : "null"})');
        return LoginResponse(
          success: false,
          statusCode: 401,
          error: 'Missing credentials for reconnection',
        );
      }
      
      final apiUrl = await storage.getCustomUrl();

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
          '$apiUrl/web/session/authenticate');
      final body =
      {
        "jsonrpc": "2.0",
        "params": {
          "db": await storage.getDatabaseName(),
          "login": username,
          "password": password
        }
      };

      final response = await SafeHttp.request(()=>http
          .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: json.encode(body)
      )
          .timeout(const Duration(seconds: 40)));
      print("------------------------------------------");
      print(response.body);
      print(response.statusCode);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // verifier que la connexion a marché
        if (data["result"]!=null && data["result"]["partner_id"]!=null) {
          final rawCookie = response.headers['set-cookie'];
          if (rawCookie != null) {
            print("Cookie reçu : $rawCookie");


            await StorageService().saveToken(rawCookie);

            return LoginResponse(success: true, token: rawCookie,statusCode: 200);
          }else{
            return LoginResponse(
              success: false,
              error: 'Connection failed: Cookie not found',
            );
          }
        }
        print('reponse apres login : ${response.body}  - ${response.statusCode}');
        return LoginResponse(
          success: false,
          error: 'Connection failed : Invalid credentials',
        );
      } else if (response.statusCode == 401) {
        return LoginResponse(
          success: false,
          statusCode: 401,
          error:
          'Invalid credentials',
        );
      } else {
        final errorData = json.decode(response.body);
        return LoginResponse(
          success: false,
          statusCode: response.statusCode,
          error: errorData['detail'] ?? 'Connection Failed',
        );
      }
    } on SocketException {
      return LoginResponse(
        success: false,
        error: 'Unable to connect to the server',
      );
    } on TimeoutException {
      return LoginResponse(success: false, error: 'Connection timeout');
    } catch (e) {
      String message;
      if(e.toString().contains("HandshakeException")){
        message = "Unable to connect to the server, check the API URL";
      }else{
        message = e.toString();
      }
      return LoginResponse(success: false, error: 'Connection failed: $message');
    }

  }
}
