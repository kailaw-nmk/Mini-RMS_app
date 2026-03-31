import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/call_state.dart';

/// Valid state transitions for the connection state machine
class ConnectionStateMachine {
  ConnectionState _state = ConnectionState.disconnected;
  DateTime? _disconnectedSince;

  // ignore: unused_field - will be used for SUSPENDED duration tracking in Week 5+
  DateTime? _suspendedSince;

  final _stateController = StreamController<ConnectionState>.broadcast();

  /// Stream of state changes
  Stream<ConnectionState> get onStateChange => _stateController.stream;

  /// Current state
  ConnectionState get currentState => _state;

  /// Duration since disconnected (for SUSPENDED/DISCONNECTED logic)
  DateTime? get disconnectedSince => _disconnectedSince;

  /// Allowed transitions from each state
  static const Map<ConnectionState, Set<ConnectionState>> _validTransitions = {
    ConnectionState.connected: {
      ConnectionState.reconnectingNetwork,
      ConnectionState.reconnectingPeer,
      ConnectionState.disconnected,
    },
    ConnectionState.reconnectingNetwork: {
      ConnectionState.connected,
      ConnectionState.suspended,
      ConnectionState.disconnected,
    },
    ConnectionState.reconnectingPeer: {
      ConnectionState.connected,
      ConnectionState.suspended,
      ConnectionState.disconnected,
    },
    ConnectionState.suspended: {
      ConnectionState.connected,
      ConnectionState.reconnectingNetwork,
      ConnectionState.reconnectingPeer,
      ConnectionState.disconnected,
    },
    ConnectionState.disconnected: {
      ConnectionState.connected,
    },
  };

  /// Attempt a state transition. Returns true if valid, false if rejected.
  bool transitionTo(ConnectionState newState) {
    if (newState == _state) return true; // No-op

    final allowed = _validTransitions[_state];
    if (allowed == null || !allowed.contains(newState)) {
      debugPrint(
        'StateMachine: REJECTED transition ${_state.name} -> ${newState.name}',
      );
      return false;
    }

    final oldState = _state;
    _state = newState;

    // Track disconnect timing
    if (newState == ConnectionState.reconnectingNetwork ||
        newState == ConnectionState.reconnectingPeer) {
      _disconnectedSince ??= DateTime.now();
    } else if (newState == ConnectionState.suspended) {
      _suspendedSince = DateTime.now();
    } else if (newState == ConnectionState.connected) {
      _disconnectedSince = null;
      _suspendedSince = null;
    } else if (newState == ConnectionState.disconnected) {
      _disconnectedSince = null;
      _suspendedSince = null;
    }

    debugPrint('StateMachine: ${oldState.name} -> ${newState.name}');
    _stateController.add(newState);
    return true;
  }

  /// Check if transition to SUSPENDED is due (5 minutes disconnected)
  bool shouldTransitionToSuspended() {
    if (_state != ConnectionState.reconnectingNetwork &&
        _state != ConnectionState.reconnectingPeer) {
      return false;
    }
    if (_disconnectedSince == null) return false;
    return DateTime.now().difference(_disconnectedSince!) >
        const Duration(minutes: 5);
  }

  /// Check if session should expire (30 minutes total)
  bool shouldSessionExpire() {
    if (_disconnectedSince == null) return false;
    return DateTime.now().difference(_disconnectedSince!) >
        const Duration(minutes: 30);
  }

  /// Reset the state machine
  void reset() {
    _state = ConnectionState.disconnected;
    _disconnectedSince = null;
    _suspendedSince = null;
  }

  void dispose() {
    _stateController.close();
  }
}
