import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:http/http.dart' show ClientException;
import 'package:geotrack_frontend/utils/constants.dart';

/// Network connection exception with optional retry support
class NetworkException implements Exception {
  final String message;
  final bool isRetryable;
  final int retryCount;

  NetworkException(this.message, {this.isRetryable = true, this.retryCount = 0});

  @override
  String toString() => 'NetworkException: $message (retryable: $isRetryable, attempts: $retryCount)';
}

/// Classe utilitaire pour encapsuler les appels HTTP avec gestion centralisée des erreurs.
class SafeHttp {
  /// Tracks if we're in long wait mode after max retries exhausted
  static bool _inLongWaitMode = false;
  static DateTime? _longWaitUntil;

  /// Check if a status code is a retryable server error (5xx)
  static bool isRetryableServerError(int statusCode) {
    return statusCode >= 500 && statusCode <= 504;
  }

  /// Check if response indicates rate limiting
  static bool isRateLimited(int statusCode) {
    return statusCode == 429;
  }

  /// Get retry delay from Retry-After header (in seconds)
  static int? getRetryAfterSeconds(http.Response response) {
    final retryAfter = response.headers['retry-after'];
    if (retryAfter == null) return null;
    return int.tryParse(retryAfter);
  }

  /// Calculate exponential backoff delay: 4^n seconds, capped at max
  static Duration calculateBackoff(int retryCount) {
    final base = Constants.httpRetryBaseSeconds;
    final maxSeconds = Constants.httpRetryMaxSeconds;
    final seconds = min(pow(base, retryCount).toInt(), maxSeconds);
    return Duration(seconds: seconds);
  }

  /// Main request method with retry logic for 5xx and 429 errors
  static Future<http.Response> request(
    Future<http.Response> Function() requestFn, {
    int retryCount = 0,
    bool isRetryAfterLongWait = false,
  }) async {
    // Check if we're in long wait mode
    if (_inLongWaitMode && _longWaitUntil != null) {
      if (DateTime.now().isBefore(_longWaitUntil!)) {
        final remaining = _longWaitUntil!.difference(DateTime.now());
        print('⏳ In long wait mode, ${remaining.inMinutes}min remaining. Request will proceed but may fail.');
      } else {
        // Long wait period is over, reset
        _inLongWaitMode = false;
        _longWaitUntil = null;
        print('✅ Long wait period ended, resuming normal retry logic');
      }
    }

    try {
      final response = await requestFn();

      // Handle rate limiting (429)
      if (isRateLimited(response.statusCode)) {
        final retryAfter = getRetryAfterSeconds(response) ?? 30;
        print('⚠️ Rate limited (429). Waiting ${retryAfter}s before retry...');
        await Future.delayed(Duration(seconds: retryAfter));
        return request(requestFn, retryCount: 0); // Reset retry count for rate limit
      }

      // Handle retryable server errors (500-504)
      if (isRetryableServerError(response.statusCode)) {
        final maxRetries = Constants.httpMaxRetryAttempts;
        
        if (retryCount < maxRetries) {
          final backoff = calculateBackoff(retryCount);
          print('⚠️ Server error ${response.statusCode}, retry ${retryCount + 1}/$maxRetries in ${backoff.inSeconds}s...');
          await Future.delayed(backoff);
          return request(requestFn, retryCount: retryCount + 1);
        } else {
          // Max retries exhausted, enter long wait mode
          final longWait = Duration(minutes: Constants.httpRetryLongWaitMinutes);
          _inLongWaitMode = true;
          _longWaitUntil = DateTime.now().add(longWait);
          print('❌ Max retries exhausted for ${response.statusCode}. Entering ${longWait.inMinutes}min wait mode.');
          
          // Don't block - throw exception so sync can continue later
          throw ServerErrorException(
            'Server error ${response.statusCode} after $maxRetries retries. Will retry in ${longWait.inMinutes} minutes.',
            statusCode: response.statusCode,
            retryAfter: longWait,
          );
        }
      }

      return response;
    } on HandshakeException catch (e) {
      print('SSL Handshake error: $e');
      throw Exception(
          'SSL Error: The server certificate is invalid. Please check the API URL.');
    } on SocketException catch (e) {
      // Network issue - retry with backoff for transient failures
      if (retryCount < Constants.httpMaxRetryAttempts) {
        final backoff = calculateBackoff(retryCount);
        print('🔌 Network error, retry ${retryCount + 1}/${Constants.httpMaxRetryAttempts} in ${backoff.inSeconds}s: $e');
        await Future.delayed(backoff);
        return request(requestFn, retryCount: retryCount + 1);
      }
      print('❌ Network error after ${Constants.httpMaxRetryAttempts} retries: $e');
      throw NetworkException(
        'Unable to connect to the server after ${Constants.httpMaxRetryAttempts} attempts. Check your Internet connection.',
        isRetryable: false,
        retryCount: retryCount,
      );
    } on HttpException catch (e) {
      print('HTTP error: $e');
      throw Exception('HTTP error: ${e.message}');
    } on FormatException catch (e) {
      print('Bad response format: $e');
      throw Exception('Invalid server response.');
    } on ClientException catch (e) {
      // Connection abort, reset, etc. - retry with backoff
      final isConnectionAbort = e.message.contains('connection abort') ||
          e.message.contains('Connection reset') ||
          e.message.contains('Connection closed');
      
      if (isConnectionAbort && retryCount < Constants.httpMaxRetryAttempts) {
        final backoff = calculateBackoff(retryCount);
        print('🔗 Connection lost, retry ${retryCount + 1}/${Constants.httpMaxRetryAttempts} in ${backoff.inSeconds}s: ${e.message}');
        await Future.delayed(backoff);
        return request(requestFn, retryCount: retryCount + 1);
      }
      print('❌ Connection error after retries: $e');
      throw NetworkException(
        'Connection lost: ${e.message}',
        isRetryable: false,
        retryCount: retryCount,
      );
    } on NetworkException {
      rethrow;
    } on ServerErrorException {
      rethrow; // Don't wrap our custom exceptions
    } on RateLimitException {
      rethrow;
    } on CustomHttpException {
      rethrow;
    } on PayloadTooLargeException {
      rethrow;
    } on ValidationException {
      rethrow;
    } on CaptivePortalException {
      rethrow;
    } on RequestTimeoutException {
      rethrow;
    } on ConflictException {
      rethrow;
    } on MethodNotAllowedException {
      rethrow;
    } on TimeoutException catch (e) {
      // Request timed out - retry with backoff
      if (retryCount < Constants.httpMaxRetryAttempts) {
        final backoff = calculateBackoff(retryCount);
        print('⏱️ Request timeout, retry ${retryCount + 1}/${Constants.httpMaxRetryAttempts} in ${backoff.inSeconds}s');
        await Future.delayed(backoff);
        return request(requestFn, retryCount: retryCount + 1);
      }
      print('❌ Timeout after ${Constants.httpMaxRetryAttempts} retries: $e');
      throw NetworkException(
        'Request timed out after ${Constants.httpMaxRetryAttempts} attempts',
        isRetryable: false,
        retryCount: retryCount,
      );
    } catch (e) {
      print('Unexpected error: $e');
      throw Exception('Unexpected error: $e');
    }
  }

  /// Reset long wait mode (call when network conditions change)
  static void resetLongWaitMode() {
    _inLongWaitMode = false;
    _longWaitUntil = null;
  }
}

class CustomHttpException implements Exception {
  final int? statusCode;
  final String message;

  CustomHttpException(this.message, {this.statusCode});

  @override
  String toString() => 'CustomHttpException($statusCode): $message';
}

class ServerErrorException implements Exception {
  final int? statusCode;
  final String message;
  final Duration? retryAfter;

  ServerErrorException(this.message, {this.statusCode, this.retryAfter});

  @override
  String toString() => 'ServerErrorException($statusCode): $message';
}

class RateLimitException implements Exception {
  final Duration retryAfter;
  final String message;

  RateLimitException(this.retryAfter, {this.message = 'Rate limited by server'});

  @override
  String toString() => 'RateLimitException: $message (retry after ${retryAfter.inSeconds}s)';
}

class PayloadTooLargeException implements Exception {
  final String message;
  final int? statusCode;

  PayloadTooLargeException(this.message, {this.statusCode = 413});

  @override
  String toString() => 'PayloadTooLargeException($statusCode): $message';
}

class ValidationException implements Exception {
  final String message;
  final Map<String, dynamic>? errors;
  final int? statusCode;

  ValidationException(this.message, {this.errors, this.statusCode = 422});

  @override
  String toString() {
    if (errors != null && errors!.isNotEmpty) {
      return 'ValidationException($statusCode): $message - $errors';
    }
    return 'ValidationException($statusCode): $message';
  }
}

class CaptivePortalException implements Exception {
  final String message;

  CaptivePortalException({this.message = 'Network requires authentication (captive portal)'});

  @override
  String toString() => 'CaptivePortalException: $message';
}

class RequestTimeoutException implements Exception {
  final String message;
  final int? statusCode;

  RequestTimeoutException(this.message, {this.statusCode = 408});

  @override
  String toString() => 'RequestTimeoutException($statusCode): $message';
}

class ConflictException implements Exception {
  final String message;
  final int? statusCode;
  final String? conflictingId;

  ConflictException(this.message, {this.statusCode = 409, this.conflictingId});

  @override
  String toString() => 'ConflictException($statusCode): $message${conflictingId != null ? ' [ID: $conflictingId]' : ''}';
}

class MethodNotAllowedException implements Exception {
  final String message;
  final int? statusCode;
  final List<String>? allowedMethods;

  MethodNotAllowedException(this.message, {this.statusCode = 405, this.allowedMethods});

  @override
  String toString() => 'MethodNotAllowedException($statusCode): $message${allowedMethods != null ? ' [Allowed: ${allowedMethods!.join(", ")}]' : ''}';
}
