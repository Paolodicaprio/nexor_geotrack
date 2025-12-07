import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geotrack_frontend/models/config_model.dart';
import 'package:geotrack_frontend/models/gps_data_model.dart';
import 'package:geotrack_frontend/utils/constants.dart';
import 'storage_service.dart';

class ApiService {
  static Future<String> getApiUrl() async {
    // Vérifier l'URL personnalisée
    final customUrl = await StorageService().getCustomUrl();
    if (customUrl != null && customUrl.isNotEmpty) {
      return customUrl.endsWith('/')
          ? customUrl.substring(0, customUrl.length - 1)
          : customUrl;
    } else {
      // Charger depuis .env ou utiliser constante
      final url = dotenv.env['API_BASE_URL'] ?? Constants.apiBaseUrl;
      return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    }
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await StorageService().getToken();
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  Future<Config> getConfig() async {
    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();

      print('🔄 GET Config from: $apiUrl/time-config');

      final response = await http
          .get(Uri.parse('$apiUrl/time-config'), headers: headers)
          .timeout(const Duration(seconds: 30));

      print('📥 Config Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return Config.fromJson(data);
      } else if (response.statusCode == 404) {
        // Configuration non trouvée, créer une configuration par défaut
        print('⚠️ Config not found, creating default...');
        return await createConfig(300, 600); // 5 min et 10 min par défaut
      } else if (response.statusCode == 401) {
        throw Exception('Non authentifié. Token invalide ou expiré');
      } else {
        throw Exception(
          'Failed to load config: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('❌ Error loading config: $e');
      rethrow;
    }
  }

  Future<GpsData> sendGpsData(GpsData data) async {
    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();

      // CORRECTION: Utiliser uniquement le format attendu par l'API
      final payload = {
        "idname": data.idname,
        "latitude": data.latitude,
        "longitude": data.longitude,
        "datetime": data.datetime.toIso8601String(),
      };

      print('📍 Sending GPS data to: $apiUrl/location');
      print('📍 Payload: $payload');

      final response = await http
          .post(
            Uri.parse('$apiUrl/location'),
            headers: headers,
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 30));

      print('📍 Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('✅ GPS data sent successfully');
        return GpsData.fromJson(responseData);
      } else if (response.statusCode == 422) {
        final error = json.decode(response.body);
        print('❌ Validation error: $error');
        throw Exception('Validation error: ${error['detail']}');
      } else if (response.statusCode == 401) {
        throw Exception('Non authentifié. Token invalide ou expiré');
      } else {
        throw Exception(
          'Failed to send GPS data: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('❌ Error sending GPS data: $e');
      rethrow;
    }
  }

  Future<List<GpsData>> getGpsData({
    String? idname,
    DateTime? dateStart,
    DateTime? dateEnd,
    int limit = 10,
  }) async {
    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();

      final params = <String, String>{};
      if (idname != null) params['idname'] = idname;
      if (dateStart != null) params['datestart'] = dateStart.toIso8601String();
      if (dateEnd != null) params['dateend'] = dateEnd.toIso8601String();
      params['limit'] = limit.toString();

      final url = Uri.parse(
        '$apiUrl/location',
      ).replace(queryParameters: params);

      print('📡 GET GPS Data from: $url');

      final response = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => GpsData.fromJson(json)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Non authentifié. Token invalide ou expiré');
      } else {
        throw Exception('Failed to load GPS data: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error loading GPS data: $e');
      rethrow;
    }
  }

  Future<Config> updateConfig(Map<String, dynamic> updates) async {
    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();

      print('🔄 PUT Request to: $apiUrl/time-config');
      print('📦 Payload: $updates');

      final response = await http
          .put(
            Uri.parse('$apiUrl/time-config'),
            headers: headers,
            body: json.encode(updates),
          )
          .timeout(const Duration(seconds: 30));

      print('📤 Response Status: ${response.statusCode}');
      print('📤 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return Config.fromJson(data);
      } else if (response.statusCode == 401) {
        throw Exception('Non authentifié. Token invalide ou expiré');
      } else {
        throw Exception(
          'Failed to update config: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('❌ Error in updateConfig: $e');
      rethrow;
    }
  }

  Future<Config> createConfig(int collectionInterval, int sendInterval) async {
    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();

      print('🆕 Creating config at: $apiUrl/time-config');

      final response = await http
          .post(
            Uri.parse('$apiUrl/time-config'),
            headers: headers,
            body: json.encode({
              'collection_interval': collectionInterval,
              'send_interval': sendInterval,
            }),
          )
          .timeout(const Duration(seconds: 30));

      print(
        '🆕 Create Config Response: ${response.statusCode} - ${response.body}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return Config.fromJson(data);
      } else if (response.statusCode == 401) {
        throw Exception('Non authentifié. Token invalide ou expiré');
      } else {
        throw Exception(
          'Failed to create config: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('❌ Error creating config: $e');
      rethrow;
    }
  }

  // Nouvelle méthode pour vérifier la santé de l'API
  Future<bool> checkApiHealth() async {
    try {
      final apiUrl = await getApiUrl();
      final response = await http
          .get(Uri.parse('$apiUrl/health'))
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      print('❌ API Health check failed: $e');
      return false;
    }
  }
}
