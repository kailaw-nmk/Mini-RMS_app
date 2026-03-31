import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Flutter interface to Android Foreground Service via MethodChannel
class ForegroundServiceManager {
  static const _channel = MethodChannel('com.tailcall/foreground_service');

  /// Start the foreground service (call this when call begins)
  static Future<void> startService() async {
    try {
      await _channel.invokeMethod('startService');
      debugPrint('ForegroundService: started');
    } on PlatformException catch (e) {
      debugPrint('ForegroundService: failed to start: ${e.message}');
    }
  }

  /// Stop the foreground service (call this when call ends)
  static Future<void> stopService() async {
    try {
      await _channel.invokeMethod('stopService');
      debugPrint('ForegroundService: stopped');
    } on PlatformException catch (e) {
      debugPrint('ForegroundService: failed to stop: ${e.message}');
    }
  }

  /// Update the notification text and duration
  static Future<void> updateNotification({
    required String statusText,
    String duration = '',
  }) async {
    try {
      await _channel.invokeMethod('updateNotification', {
        'statusText': statusText,
        'duration': duration,
      });
    } on PlatformException catch (e) {
      debugPrint('ForegroundService: failed to update: ${e.message}');
    }
  }

  /// Check if battery optimization exclusion is granted
  static Future<bool> isBatteryOptimizationExcluded() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isBatteryOptimizationExcluded');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Request battery optimization exclusion from the user
  static Future<void> requestBatteryOptimizationExclusion() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimizationExclusion');
    } on PlatformException catch (e) {
      debugPrint(
          'ForegroundService: battery optimization request failed: ${e.message}');
    }
  }
}
