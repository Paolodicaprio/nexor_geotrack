import 'dart:convert';
import 'dart:developer';
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
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<Config> getConfig() async {
    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();

      log('🔄 GET Config from: $apiUrl/time-config');

      final response = await http
          .get(Uri.parse('$apiUrl/time-config'), headers: headers)
          .timeout(const Duration(seconds: 30));

      log('📥 Config Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return Config.fromJson(data);
      } else if (response.statusCode == 404) {
        // Configuration non trouvée, créer une configuration par défaut
        log('⚠️ Config not found, creating default...');
        return await createConfig(300, 600); // 5 min et 10 min par défaut
      } else {
        throw Exception(
          'Failed to load config: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      log('❌ Error loading config: $e');
      rethrow;
    }
  }

  Future<GpsData> sendGpsData(GpsData data) async {
    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();

      // Tester les deux formats possibles
      final attempts = [
        // Format 1: latitude/longitude (selon l'erreur)
        {
          "idname": data.idname,
          "latitude": data.latitude,
          "longitude": data.longitude,
          "datetime": data.datetime.toIso8601String(),
        },
        // Format 2: lat/lon (selon la documentation)
        {
          "idname": data.idname,
          "lat": data.latitude,
          "lon": data.longitude,
          "datetime": data.datetime.toIso8601String(),
        },
        // Format 3: Tous les champs possibles
        {
          "idname": data.idname,
          "latitude": data.latitude,
          "longitude": data.longitude,
          "lat": data.latitude,
          "lon": data.longitude,
          "datetime": data.datetime.toIso8601String(),
        },
      ];

      for (int i = 0; i < attempts.length; i++) {
        try {
          final body = attempts[i];
          log('📍 Attempt ${i + 1}: Sending GPS data with format ${i + 1}');
          log('📍 Payload: $body');

          final response = await http
              .post(
                Uri.parse('$apiUrl/location'),
                headers: headers,
                body: json.encode(body),
              )
              .timeout(const Duration(seconds: 30));

          log('📍 Response ${i + 1}: ${response.statusCode}');

          if (response.statusCode == 200) {
            final responseData = json.decode(response.body);
            log('✅ Success with format ${i + 1}');
            return GpsData.fromJson(responseData);
          } else if (response.statusCode == 422) {
            log('⚠️ Format ${i + 1} failed, trying next...');
            continue;
          } else {
            throw Exception(
              'Failed to send GPS data: ${response.statusCode} - ${response.body}',
            );
          }
        } catch (e) {
          if (i == attempts.length - 1) {
            rethrow;
          }
          log('⚠️ Attempt ${i + 1} error: $e');
        }
      }

      throw Exception('All format attempts failed');
    } catch (e) {
      log('❌ Error sending GPS data: $e');
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

      log('📡 GET GPS Data from: $url');

      final response = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => GpsData.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load GPS data: ${response.statusCode}');
      }
    } catch (e) {
      log('❌ Error loading GPS data: $e');
      rethrow;
    }
  }

  Future<Config> updateConfig(Map<String, dynamic> updates) async {
    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();

      log('🔄 PUT Request to: $apiUrl/time-config');
      log('📦 Payload: $updates');

      final response = await http
          .put(
            Uri.parse('$apiUrl/time-config'),
            headers: headers,
            body: json.encode(updates),
          )
          .timeout(const Duration(seconds: 30));

      log('📤 Response Status: ${response.statusCode}');
      log('📤 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return Config.fromJson(data);
      } else {
        throw Exception(
          'Failed to update config: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      log('❌ Error in updateConfig: $e');
      rethrow;
    }
  }

  Future<Config> createConfig(int collectionInterval, int sendInterval) async {
    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();

      log('🆕 Creating config at: $apiUrl/time-config');

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

      log(
        '🆕 Create Config Response: ${response.statusCode} - ${response.body}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return Config.fromJson(data);
      } else {
        throw Exception(
          'Failed to create config: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      log('❌ Error creating config: $e');
      rethrow;
    }
  }
}
