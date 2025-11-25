import 'dart:convert';
import 'package:geotrack_frontend/services/notification_service.dart';
import 'package:geotrack_frontend/services/safe_http.dart';
import 'package:http/http.dart' as http;
import 'package:geotrack_frontend/models/config_model.dart';
import 'package:geotrack_frontend/models/gps_data_model.dart';
import 'package:geotrack_frontend/utils/constants.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/response_checker.dart';
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

      final response = await SafeHttp.request(() => http.get(
          Uri.parse('$apiUrl/transport_tracking/config'),
          headers: headers).timeout(Duration(seconds: 30)));

      if (response.statusCode == 200 && !isSessionInvalid(response)) {
        return Config.fromJson(json.decode(response.body));
      } else if (isSessionInvalid(response)) {
        throw CustomHttpException("Session Expired.",statusCode: 401);
      } else if (response.statusCode == 404) {
        return Config.fromDefault();
      } else {
        throw CustomHttpException('Erreur ${response.statusCode}: ${response.body}',statusCode: response.statusCode);
      }
    } catch (e) {
      throw Exception('Impossible de charger la config : $e');
    }
  }


  Future<bool> sendGpsDataJsonList(List<Map<String, dynamic>> data) async {
    final deviceCode = await StorageService().getDeviceCode();
    if (deviceCode == null) {
      throw CustomHttpException(
        'Could not send data: You must set a device code in settings',
      );
    }

    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();
      print(" headersss: $headers");
      final body = jsonEncode({"positions": data});
      final url = Uri.parse('$apiUrl/transport_tracking/$deviceCode/positions');

      final response = await SafeHttp.request(
            () => http.post(url, headers: headers, body: body),
      );

      if (response.statusCode == 200 && !isSessionInvalid(response)) {
        print('✅ GPS data synced successfully: ${response.body}');
        return true;
      }else if(isSessionInvalid(response)){
        throw CustomHttpException("Session Expired.",statusCode: 401);
      }

      // --- Gestion des erreurs HTTP ---
      String errorMessage;
      try {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        if (responseData.containsKey('message')) {
          errorMessage = responseData['message'];
        } else if (responseData.containsKey('status')) {
          errorMessage = 'Status: ${responseData['status']}';
        } else {
          errorMessage = response.body;
        }
      } catch (_) {
        errorMessage = 'Failed to send GPS data';
      }
      throw Exception(
        errorMessage,
      );

    } catch (e) {
      print('❌ Failed to send GPS data: $e');
      rethrow;
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

      final response = await SafeHttp.request(()=>http.get(uri, headers: headers));

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

      final response = await SafeHttp.request(()=>http.put(
        Uri.parse('$apiUrl/transport_tracking/config'),
        headers: headers,
        body: json.encode(updates),
      ));

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

      final response = await SafeHttp.request(()=>http.post(
        Uri.parse('$apiUrl/transport_tracking/config'),
        headers: headers,
        body: json.encode(config),
      ));

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
