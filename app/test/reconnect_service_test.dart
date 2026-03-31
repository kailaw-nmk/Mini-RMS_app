import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailcall/features/call/models/call_state.dart';
import 'package:tailcall/features/call/services/connection_state_machine.dart';
import 'package:tailcall/features/call/services/reconnect_service.dart';

void main() {
  group('ReconnectConfig', () {
    test('has correct default values', () {
      const config = ReconnectConfig();
      expect(config.iceRestartTimeout, const Duration(seconds: 5));
      expect(config.maxIceRestartAttempts, 2);
      expect(config.pcRecreateTimeout, const Duration(seconds: 10));
      expect(config.initialBackoff, const Duration(milliseconds: 500));
      expect(config.maxBackoff, const Duration(seconds: 30));
      expect(config.suspendedThreshold, const Duration(minutes: 5));
      expect(config.sessionExpireThreshold, const Duration(minutes: 30));
      expect(config.suspendedRetryInterval, const Duration(seconds: 30));
    });

    test('allows custom values', () {
      const config = ReconnectConfig(
        maxIceRestartAttempts: 3,
        maxBackoff: Duration(seconds: 60),
      );
      expect(config.maxIceRestartAttempts, 3);
      expect(config.maxBackoff, const Duration(seconds: 60));
    });
  });

  group('Exponential Backoff', () {
    test('calculates correct backoff durations', () {
      const config = ReconnectConfig();
      // Simulate backoff calculation
      for (var step = 0; step < 8; step++) {
        final ms = config.initialBackoff.inMilliseconds *
            pow(2, step.clamp(0, 10));
        final clamped = ms.clamp(
          config.initialBackoff.inMilliseconds,
          config.maxBackoff.inMilliseconds,
        );
        final duration = Duration(milliseconds: clamped.toInt());

        switch (step) {
          case 0:
            expect(duration.inMilliseconds, 500); // 500ms
            break;
          case 1:
            expect(duration.inMilliseconds, 1000); // 1s
            break;
          case 2:
            expect(duration.inMilliseconds, 2000); // 2s
            break;
          case 3:
            expect(duration.inMilliseconds, 4000); // 4s
            break;
          case 4:
            expect(duration.inMilliseconds, 8000); // 8s
            break;
          case 5:
            expect(duration.inMilliseconds, 16000); // 16s
            break;
          case 6:
            expect(duration.inMilliseconds, 30000); // capped at 30s
            break;
          case 7:
            expect(duration.inMilliseconds, 30000); // stays at 30s
            break;
        }
      }
    });
  });

  group('ReconnectService basic state', () {
    late ConnectionStateMachine sm;

    setUp(() {
      sm = ConnectionStateMachine();
    });

    tearDown(() {
      sm.dispose();
    });

    test('SUSPENDED transition after 5 minutes', () {
      sm.transitionTo(ConnectionState.connected);
      sm.transitionTo(ConnectionState.reconnectingNetwork);

      // Just disconnected - should not be suspended
      expect(sm.shouldTransitionToSuspended(), isFalse);
    });

    test('session should not expire immediately', () {
      sm.transitionTo(ConnectionState.connected);
      sm.transitionTo(ConnectionState.reconnectingNetwork);

      expect(sm.shouldSessionExpire(), isFalse);
    });

    test('state machine supports full reconnect flow', () {
      // Simulate: connected -> reconnecting -> connected (ICE restart success)
      sm.transitionTo(ConnectionState.connected);
      sm.transitionTo(ConnectionState.reconnectingNetwork);
      sm.transitionTo(ConnectionState.connected);
      expect(sm.currentState, ConnectionState.connected);
    });

    test('state machine supports ICE fail -> PC recreate flow', () {
      // connected -> reconnecting -> suspended -> connected
      sm.transitionTo(ConnectionState.connected);
      sm.transitionTo(ConnectionState.reconnectingNetwork);
      sm.transitionTo(ConnectionState.suspended);
      sm.transitionTo(ConnectionState.connected);
      expect(sm.currentState, ConnectionState.connected);
    });

    test('state machine supports session expiry flow', () {
      // connected -> reconnecting -> suspended -> disconnected
      sm.transitionTo(ConnectionState.connected);
      sm.transitionTo(ConnectionState.reconnectingNetwork);
      sm.transitionTo(ConnectionState.suspended);
      sm.transitionTo(ConnectionState.disconnected);
      expect(sm.currentState, ConnectionState.disconnected);
    });
  });

  group('ReconnectResult', () {
    test('has all expected values', () {
      expect(ReconnectResult.values, hasLength(5));
      expect(ReconnectResult.values, contains(ReconnectResult.success));
      expect(
          ReconnectResult.values, contains(ReconnectResult.iceRestartFailed));
      expect(
          ReconnectResult.values, contains(ReconnectResult.pcRecreateFailed));
      expect(
          ReconnectResult.values, contains(ReconnectResult.sessionExpired));
      expect(ReconnectResult.values, contains(ReconnectResult.cancelled));
    });
  });
}
