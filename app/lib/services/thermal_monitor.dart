import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thermal state levels
enum ThermalState {
  nominal, // Normal operating temperature
  fair, // Slightly warm
  serious, // Hot - should reduce load
  critical, // Very hot - must reduce load immediately
}

/// Callback for thermal state changes
typedef ThermalCallback = void Function(ThermalState state);

/// Monitors device temperature via platform channel
/// On Android: uses PowerManager thermal API (API 29+)
/// On iOS: uses ProcessInfo.thermalState (stub for now)
class ThermalMonitor {
  static const _channel = MethodChannel('com.tailcall/thermal');
  static Timer? _pollTimer;
  static ThermalState _currentState = ThermalState.nominal;
  static final _stateController = StreamController<ThermalState>.broadcast();

  /// Stream of thermal state changes
  static Stream<ThermalState> get onThermalStateChange =>
      _stateController.stream;

  /// Current thermal state
  static ThermalState get currentState => _currentState;

  /// Start monitoring (polls every 30 seconds)
  static void start() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _poll());
    _poll(); // Initial check
    debugPrint('ThermalMonitor: started');
  }

  /// Stop monitoring
  static void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    debugPrint('ThermalMonitor: stopped');
  }

  static Future<void> _poll() async {
    try {
      final level = await _channel.invokeMethod<int>('getThermalState');
      final newState = _fromLevel(level ?? 0);
      if (newState != _currentState) {
        _currentState = newState;
        _stateController.add(newState);
        debugPrint('ThermalMonitor: state changed to ${newState.name}');
      }
    } on PlatformException {
      // Platform doesn't support thermal monitoring
    } on MissingPluginException {
      // Running on platform without native implementation
    }
  }

  static ThermalState _fromLevel(int level) {
    switch (level) {
      case 0:
        return ThermalState.nominal;
      case 1:
        return ThermalState.fair;
      case 2:
        return ThermalState.serious;
      case >= 3:
        return ThermalState.critical;
      default:
        return ThermalState.nominal;
    }
  }

  /// Whether video should be disabled due to heat
  static bool get shouldDisableVideo =>
      _currentState == ThermalState.serious ||
      _currentState == ThermalState.critical;

  /// Whether audio bitrate should be reduced
  static bool get shouldReduceBitrate => _currentState == ThermalState.critical;
}
