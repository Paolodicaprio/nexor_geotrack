import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geotrack_frontend/services/storage_service.dart';
import 'package:geotrack_frontend/utils/constants.dart';
import 'package:geotrack_frontend/services/api_service.dart';

class HealthService {
  static Future<Map<String, dynamic>> checkApiStatus() async {
    try {
      final customUrl = await StorageService().getCustomUrl();
      final apiUrl = customUrl ?? Constants.apiBaseUrl;

      final response = await http
          .get(Uri.parse('$apiUrl/health'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'status': 'healthy',
          'message': 'API disponible',
          'timestamp': data is String ? data : 'N/A',
        };
      } else {
        return {
          'status': 'unhealthy',
          'message': 'API indisponible (${response.statusCode})',
          'timestamp': null,
        };
      }
    } catch (e) {
      return {
        'status': 'error',
        'message': 'Erreur de connexion: $e',
        'timestamp': null,
      };
    }
  }

  static Future<Map<String, dynamic>> checkAuthenticationStatus() async {
    try {
      final apiService = ApiService();
      await apiService
          .getConfig(); // Si cette requête réussit, l'authentification est valide

      return {'status': 'authenticated', 'message': 'Utilisateur authentifié'};
    } catch (e) {
      if (e.toString().contains('401') ||
          e.toString().contains('Non authentifié')) {
        return {
          'status': 'unauthenticated',
          'message': 'Token invalide ou expiré',
        };
      } else {
        return {'status': 'error', 'message': 'Erreur de vérification: $e'};
      }
    }
  }

  static Future<Map<String, dynamic>> getFullHealthStatus() async {
    final apiStatus = await checkApiStatus();
    final authStatus = await checkAuthenticationStatus();

    return {
      'api': apiStatus,
      'authentication': authStatus,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}
