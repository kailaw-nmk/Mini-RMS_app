import 'package:flutter_test/flutter_test.dart';
import 'package:tailcall/features/call/models/call_state.dart';
import 'package:tailcall/features/call/services/connection_state_machine.dart';

void main() {
  late ConnectionStateMachine sm;

  setUp(() {
    sm = ConnectionStateMachine();
  });

  tearDown(() {
    sm.dispose();
  });

  group('ConnectionStateMachine', () {
    test('starts in disconnected state', () {
      expect(sm.currentState, ConnectionState.disconnected);
    });

    test('allows disconnected -> connected', () {
      expect(sm.transitionTo(ConnectionState.connected), isTrue);
      expect(sm.currentState, ConnectionState.connected);
    });

    test('allows connected -> reconnectingNetwork', () {
      sm.transitionTo(ConnectionState.connected);
      expect(sm.transitionTo(ConnectionState.reconnectingNetwork), isTrue);
      expect(sm.currentState, ConnectionState.reconnectingNetwork);
    });

    test('allows connected -> reconnectingPeer', () {
      sm.transitionTo(ConnectionState.connected);
      expect(sm.transitionTo(ConnectionState.reconnectingPeer), isTrue);
      expect(sm.currentState, ConnectionState.reconnectingPeer);
    });

    test('allows reconnectingNetwork -> connected', () {
      sm.transitionTo(ConnectionState.connected);
      sm.transitionTo(ConnectionState.reconnectingNetwork);
      expect(sm.transitionTo(ConnectionState.connected), isTrue);
    });

    test('allows reconnectingNetwork -> suspended', () {
      sm.transitionTo(ConnectionState.connected);
      sm.transitionTo(ConnectionState.reconnectingNetwork);
      expect(sm.transitionTo(ConnectionState.suspended), isTrue);
    });

    test('allows suspended -> connected', () {
      sm.transitionTo(ConnectionState.connected);
      sm.transitionTo(ConnectionState.reconnectingNetwork);
      sm.transitionTo(ConnectionState.suspended);
      expect(sm.transitionTo(ConnectionState.connected), isTrue);
    });

    test('allows suspended -> disconnected', () {
      sm.transitionTo(ConnectionState.connected);
      sm.transitionTo(ConnectionState.reconnectingNetwork);
      sm.transitionTo(ConnectionState.suspended);
      expect(sm.transitionTo(ConnectionState.disconnected), isTrue);
    });

    test('allows any -> disconnected (call end)', () {
      sm.transitionTo(ConnectionState.connected);
      expect(sm.transitionTo(ConnectionState.disconnected), isTrue);
    });

    test('rejects disconnected -> reconnectingNetwork', () {
      expect(sm.transitionTo(ConnectionState.reconnectingNetwork), isFalse);
      expect(sm.currentState, ConnectionState.disconnected);
    });

    test('rejects disconnected -> suspended', () {
      expect(sm.transitionTo(ConnectionState.suspended), isFalse);
    });

    test('rejects connected -> suspended (must go through reconnecting)', () {
      sm.transitionTo(ConnectionState.connected);
      expect(sm.transitionTo(ConnectionState.suspended), isFalse);
    });

    test('same state transition is no-op (returns true)', () {
      sm.transitionTo(ConnectionState.connected);
      expect(sm.transitionTo(ConnectionState.connected), isTrue);
    });

    test('tracks disconnect timing', () {
      sm.transitionTo(ConnectionState.connected);
      expect(sm.disconnectedSince, isNull);

      sm.transitionTo(ConnectionState.reconnectingNetwork);
      expect(sm.disconnectedSince, isNotNull);
    });

    test('clears disconnect timing on reconnect', () {
      sm.transitionTo(ConnectionState.connected);
      sm.transitionTo(ConnectionState.reconnectingNetwork);
      expect(sm.disconnectedSince, isNotNull);

      sm.transitionTo(ConnectionState.connected);
      expect(sm.disconnectedSince, isNull);
    });

    test('emits state changes on stream', () async {
      final states = <ConnectionState>[];
      sm.onStateChange.listen(states.add);

      sm.transitionTo(ConnectionState.connected);
      sm.transitionTo(ConnectionState.reconnectingNetwork);
      sm.transitionTo(ConnectionState.connected);

      await Future.delayed(Duration.zero);

      expect(states, [
        ConnectionState.connected,
        ConnectionState.reconnectingNetwork,
        ConnectionState.connected,
      ]);
    });

    test('reset returns to disconnected', () {
      sm.transitionTo(ConnectionState.connected);
      sm.transitionTo(ConnectionState.reconnectingNetwork);
      sm.reset();

      expect(sm.currentState, ConnectionState.disconnected);
      expect(sm.disconnectedSince, isNull);
    });

    test('shouldTransitionToSuspended is false when connected', () {
      sm.transitionTo(ConnectionState.connected);
      expect(sm.shouldTransitionToSuspended(), isFalse);
    });

    test('shouldSessionExpire is false when just disconnected', () {
      sm.transitionTo(ConnectionState.connected);
      sm.transitionTo(ConnectionState.reconnectingNetwork);
      expect(sm.shouldSessionExpire(), isFalse);
    });
  });
}
