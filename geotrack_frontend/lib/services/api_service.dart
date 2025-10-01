import 'dart:convert';
import 'package:geotrack_frontend/services/notification_service.dart';
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
    var rawCookie = await StorageService().getToken();
    if (rawCookie!=null){
      rawCookie = rawCookie.split(';').first;
    }
    return {
      'Content-Type': 'application/json',
      "Cookie": rawCookie ?? "",
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
          .get(Uri.parse('$apiUrl/transport_tracking/config'), headers: headers)
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
          "position_sampling_interval": 300,
          "position_sync_interval": 600
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
      final deviceCode = await StorageService().getOrCreateDeviceId();
      final body = jsonEncode({
        "positions": [
         data.toApiJson()
        ]
      });
      final url = Uri.parse('$apiUrl/transport_tracking/$deviceCode/positions');
      print(url);
      print(headers);
      print('body :::::$body');
      final response = await http.post(url, headers: headers, body: body );

      if (response.statusCode == 200) {
        print(response.body);
        final responseData = json.decode(response.body);
        return GpsData.fromJson(responseData);
      } else {
        print('Failed to send GPS data: ${response.statusCode} - ${response.body}');
        throw Exception(
          'Failed to send GPS data: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {

      print('Failed to send GPS data surveillé: $e');

      throw Exception('Failed to send GPS data: $e');
    }
  }

  Future<void> sendGpsDataJsonList(List<Map<String, dynamic>> data) async {
    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();
      final deviceCode = await StorageService().getOrCreateDeviceId();
      final body = jsonEncode({"positions": data});
      final url = Uri.parse('$apiUrl/transport_tracking/$deviceCode/positions');

      print(url);
      print(headers);
      print('body :::::$body');

      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode == 200) {
        print('✅ GPS data synced successfully: ${response.body}');
        return; // tout est OK
      }

      // Gestion des erreurs
      String errorMessage = 'Erreur inconnue';
      try {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        if (responseData.containsKey('message')) {
          errorMessage = responseData['message'];
        } else if (responseData.containsKey('status')) {
          errorMessage = 'Status: ${responseData['status']}';
        } else {
          errorMessage = response.body; // fallback
        }
      } catch (_) {
        errorMessage = 'Failed to send GPS data: ${response.statusCode} - ${response.body}';
      }
      // Lever l’exception si nécessaire
      throw Exception(errorMessage);

    } catch (e) {
      print('❌ Failed to send GPS data: $e');
      rethrow; // pour que l’appelant puisse gérer aussi
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

      print('🔄 PUT Request to: $apiUrl/transport_tracking/config');
      print('📦 Payload: $updates');

      final response = await http.put(
        Uri.parse('$apiUrl/transport_tracking/config'),
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

      print('🔄 POST Request to: $apiUrl/transport_tracking/config');
      print('📦 Payload: $config');

      final response = await http.post(
        Uri.parse('$apiUrl/transport_tracking/config'),
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
