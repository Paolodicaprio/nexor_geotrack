import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geotrack_frontend/models/config_model.dart';
import 'package:geotrack_frontend/models/gps_data_model.dart';
import 'package:geotrack_frontend/utils/constants.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'storage_service.dart';

class ApiService {
  static Future<String> getApiUrl() async {
    final customUrl = await StorageService().getCustomUrl();
    if (customUrl != null && customUrl.isNotEmpty) {
      return customUrl;
    } else {
      return dotenv.get('API_BASE_URL', fallback: Constants.apiBaseUrl);
    }
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await StorageService().getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<bool> testConnection() async {
    try {
      final apiUrl = await getApiUrl();
      final response = await http.get(Uri.parse('$apiUrl/health'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<Config> getConfig() async {
    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();

      final response = await http
          .get(Uri.parse('$apiUrl/time-config'), headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return Config.fromJson(data);
      } else if (response.statusCode == 401) {
        // Token expiré - déconnecter l'utilisateur
        await StorageService().deleteToken();
        throw Exception('Token expiré - Veuillez vous reconnecter');
      }else if(response.statusCode == 404 ){
        // créer une config par defaut
        final defaultConfig = {
          "collection_interval": 300,
          "send_interval": 600
        };
        final config = await createConfig(defaultConfig);
        return config;
      } else {
        throw Exception(
          'Failed to load config: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      if (e.toString().contains('Token expiré')) {
        rethrow; // Propager l'erreur d'authentification
      }
      throw Exception('Failed to load config: $e');
    }
  }

  Future<GpsData> sendGpsData(GpsData data) async {
    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();

      final response = await http.post(
        Uri.parse('$apiUrl/location'),
        headers: headers,
        body: json.encode(data.toApiJson()), // Utiliser le format API
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return GpsData.fromJson(responseData);
      } else {
        throw Exception(
          'Failed to send GPS data: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Failed to send GPS data: $e');
    }
  }

  Future<List<GpsData>> getGpsData({
    String? deviceId,
    DateTime? dateStart,
    DateTime? dateEnd,
    int limit = 10,
  }) async {
    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();

      final params = <String, String>{};
      if (deviceId != null) params['idname'] = deviceId;
      if (dateStart != null) params['datestart'] = dateStart.toIso8601String();
      if (dateEnd != null) params['dateend'] = dateEnd.toIso8601String();
      params['limit'] = limit.toString();

      final uri = Uri.parse(
        '$apiUrl/location',
      ).replace(queryParameters: params);

      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => GpsData.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load GPS data: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load GPS data: $e');
    }
  }

  Future<Config> updateConfig(Map<String, dynamic> updates) async {
    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();

      print('🔄 PUT Request to: $apiUrl/time-config');
      print('📦 Payload: $updates');

      final response = await http.put(
        Uri.parse('$apiUrl/time-config'),
        headers: headers,
        body: json.encode(updates),
      );

      print('📤 Response Status: ${response.statusCode}');
      print('📤 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return Config.fromJson(data);
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

  Future<Config> createConfig(Map<String, dynamic> config) async {
    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();

      print('🔄 POST Request to: $apiUrl/time-config');
      print('📦 Payload: $config');

      final response = await http.post(
        Uri.parse('$apiUrl/time-config'),
        headers: headers,
        body: json.encode(config),
      );

      print('📤 Response Status: ${response.statusCode}');
      print('📤 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return Config.fromJson(data);
      } else {
        throw Exception(
          'Failed to create config: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('❌ Error in createConfig: $e');
      rethrow;
    }
  }
}
