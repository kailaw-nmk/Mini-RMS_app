import 'package:flutter_test/flutter_test.dart';
import 'package:tailcall/features/call/models/call_state.dart';

void main() {
  group('CallSession', () {
    test('creates with default values', () {
      final session = CallSession(
        sessionId: 'sess_001',
        peerIp: '100.64.0.12',
        startedAt: DateTime(2026, 3, 28),
      );

      expect(session.sessionId, 'sess_001');
      expect(session.peerIp, '100.64.0.12');
      expect(session.mode, 'audio');
      expect(session.connectionState, ConnectionState.disconnected);
      expect(session.disconnectCount, 0);
    });

    test('copyWith preserves unchanged fields', () {
      final session = CallSession(
        sessionId: 'sess_001',
        peerIp: '100.64.0.12',
        startedAt: DateTime(2026, 3, 28),
      );

      final updated =
          session.copyWith(connectionState: ConnectionState.connected);

      expect(updated.sessionId, 'sess_001');
      expect(updated.peerIp, '100.64.0.12');
      expect(updated.connectionState, ConnectionState.connected);
    });

    test('copyWith updates specified fields', () {
      final session = CallSession(
        sessionId: 'sess_001',
        peerIp: '100.64.0.12',
        startedAt: DateTime(2026, 3, 28),
      );

      final updated = session.copyWith(
        connectionState: ConnectionState.reconnectingNetwork,
        disconnectCount: 3,
      );

      expect(updated.connectionState, ConnectionState.reconnectingNetwork);
      expect(updated.disconnectCount, 3);
    });

    test('stateKey returns correct strings', () {
      final session = CallSession(
        sessionId: 'sess_001',
        peerIp: '100.64.0.12',
        startedAt: DateTime(2026, 3, 28),
      );

      expect(
        session.copyWith(connectionState: ConnectionState.connected).stateKey,
        'CONNECTED',
      );
      expect(
        session
            .copyWith(connectionState: ConnectionState.reconnectingNetwork)
            .stateKey,
        'RECONNECTING_NETWORK',
      );
      expect(
        session
            .copyWith(connectionState: ConnectionState.reconnectingPeer)
            .stateKey,
        'RECONNECTING_PEER',
      );
      expect(
        session.copyWith(connectionState: ConnectionState.suspended).stateKey,
        'SUSPENDED',
      );
      expect(
        session
            .copyWith(connectionState: ConnectionState.disconnected)
            .stateKey,
        'DISCONNECTED',
      );
    });
  });

  group('ConnectionState', () {
    test('has all expected values', () {
      expect(ConnectionState.values, hasLength(5));
      expect(ConnectionState.values, contains(ConnectionState.connected));
      expect(
          ConnectionState.values, contains(ConnectionState.reconnectingNetwork));
      expect(
          ConnectionState.values, contains(ConnectionState.reconnectingPeer));
      expect(ConnectionState.values, contains(ConnectionState.suspended));
      expect(ConnectionState.values, contains(ConnectionState.disconnected));
    });
  });
}
