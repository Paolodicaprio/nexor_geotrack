import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';

/// Service to help manage battery optimization settings on Android
class PowerOptimizationsService {
  static const MethodChannel _channel = MethodChannel('com.nexor.geotrack/battery');

  /// Request the user to ignore battery optimizations for this app
  /// This opens Android settings where the user can grant the exemption
  /// Returns true if the intent was successfully launched, false otherwise
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final bool result = await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
      return result;
    } on PlatformException catch (e) {
      developer.log(
        "Failed to request battery optimization exemption",
        name: 'PowerOptimizationsService',
        error: e.message,
      );
      return false;
    }
  }

  /// Check if battery optimizations are currently ignored for this app
  /// Returns true if the app is whitelisted (not optimized)
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final bool result = await _channel.invokeMethod('isIgnoringBatteryOptimizations');
      return result;
    } on PlatformException catch (e) {
      developer.log(
        "Failed to check battery optimization status",
        name: 'PowerOptimizationsService',
        error: e.message,
      );
      return false;
    }
  }
}
