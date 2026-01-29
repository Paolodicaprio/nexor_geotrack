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

      // Handle 2xx success responses
      if (isSuccessResponse(response) && !isSessionInvalid(response)) {
        // Handle 204 No Content - return default config
        if (hasEmptyBody(response)) {
          return Config.fromDefault();
        }
        return Config.fromJson(json.decode(response.body));
      } else if (isSessionInvalid(response)) {
        throw CustomHttpException("Session Expired.",statusCode: 401);
      } else if (response.statusCode == 404) {
        return Config.fromDefault();
      } else {
        throw CustomHttpException('Erreur ${response.statusCode}: ${response.body}',statusCode: response.statusCode);
      }
    } on NetworkException catch (e) {
      throw Exception('Config fetch failed (network): ${e.message}');
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

      // Handle 2xx success responses (200, 201, 204)
      if (isSuccessResponse(response) && !isSessionInvalid(response)) {
        print('✅ GPS data synced successfully: ${hasEmptyBody(response) ? "(no content)" : response.body}');
        return true;
      } else if (isSessionInvalid(response)) {
        throw CustomHttpException("Session Expired.",statusCode: 401);
      }

      // Handle 413 Payload Too Large - caller should retry with smaller chunks
      if (response.statusCode == 413) {
        throw PayloadTooLargeException(
          'Payload too large (${data.length} items). Try smaller batches.',
          statusCode: 413,
        );
      }

      // Handle 422 Unprocessable Entity - validation errors
      if (response.statusCode == 422) {
        Map<String, dynamic>? validationErrors;
        String errorMsg = 'Validation failed';
        try {
          final responseData = jsonDecode(response.body);
          if (responseData is Map<String, dynamic>) {
            validationErrors = responseData['errors'] ?? responseData['detail'];
            errorMsg = responseData['message'] ?? errorMsg;
          }
        } catch (_) {}
        throw ValidationException(errorMsg, errors: validationErrors, statusCode: 422);
      }

      // Handle 511 Network Authentication Required (captive portal)
      if (response.statusCode == 511) {
        throw CaptivePortalException(
          message: 'Network requires authentication. Please connect to WiFi/network first.',
        );
      }

      // Handle 408 Request Timeout - server didn't receive request in time
      if (response.statusCode == 408) {
        throw RequestTimeoutException(
          'Request timed out. Server did not receive the data in time.',
          statusCode: 408,
        );
      }

      // Handle 409 Conflict - likely duplicate UUID
      if (response.statusCode == 409) {
        String? conflictingId;
        try {
          final responseData = jsonDecode(response.body);
          if (responseData is Map<String, dynamic>) {
            conflictingId = responseData['conflicting_id']?.toString() ?? 
                            responseData['uuid']?.toString();
          }
        } catch (_) {}
        throw ConflictException(
          'Data conflict detected. Some records may already exist on server.',
          statusCode: 409,
          conflictingId: conflictingId,
        );
      }

      // Handle 405 Method Not Allowed - API configuration error
      if (response.statusCode == 405) {
        List<String>? allowedMethods;
        final allowHeader = response.headers['allow'];
        if (allowHeader != null) {
          allowedMethods = allowHeader.split(',').map((m) => m.trim()).toList();
        }
        throw MethodNotAllowedException(
          'HTTP method not allowed for this endpoint.',
          statusCode: 405,
          allowedMethods: allowedMethods,
        );
      }

      // --- Gestion des autres erreurs HTTP ---
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
        errorMessage = 'Failed to send GPS data (${response.statusCode})';
      }
      throw CustomHttpException(errorMessage, statusCode: response.statusCode);

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

      if (isSuccessResponse(response)) {
        // Handle 204 No Content - return empty list
        if (hasEmptyBody(response)) {
          return [];
        }
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

      if (isSuccessResponse(response)) {
        // Handle 204 No Content
        if (hasEmptyBody(response)) {
          return Config.fromJson(updates); // Return the updates as config
        }
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

      if (isSuccessResponse(response)) {
        // Handle 204 No Content
        if (hasEmptyBody(response)) {
          return Config.fromJson(config); // Return the config as created
        }
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

  /// Send a heartbeat ping to the server to indicate device is online
  Future<bool> sendHeartbeat() async {
    try {
      final apiUrl = await getApiUrl();
      final headers = await _getHeaders();
      final deviceCode = await StorageService().getDeviceCode();
      
      if (deviceCode == null || deviceCode.isEmpty) {
        print('⚠️ No device code set, skipping heartbeat');
        return false;
      }

      final body = {
        "device_id": deviceCode,
        "timestamp": DateTime.now().toIso8601String(),
        "service_status": "running",
      };

      final response = await SafeHttp.request(
        () => http.post(
          Uri.parse('$apiUrl/heartbeat/'),
          headers: headers,
          body: json.encode(body),
        ).timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        print('⚠️ Heartbeat failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Heartbeat error: $e');
      return false;
    }
  }
}
