/// Connection states for the call
enum ConnectionState {
  connected,
  reconnectingNetwork,
  reconnectingPeer,
  suspended,
  disconnected,
}

/// Call session information
class CallSession {
  final String sessionId;
  final String peerIp;
  final String peerDeviceId;
  final String mode;
  final DateTime startedAt;
  final ConnectionState connectionState;
  final int disconnectCount;
  final Duration totalDisconnectDuration;

  const CallSession({
    required this.sessionId,
    required this.peerIp,
    this.peerDeviceId = '',
    this.mode = 'audio',
    required this.startedAt,
    this.connectionState = ConnectionState.disconnected,
    this.disconnectCount = 0,
    this.totalDisconnectDuration = Duration.zero,
  });

  CallSession copyWith({
    String? sessionId,
    String? peerIp,
    String? peerDeviceId,
    String? mode,
    DateTime? startedAt,
    ConnectionState? connectionState,
    int? disconnectCount,
    Duration? totalDisconnectDuration,
  }) {
    return CallSession(
      sessionId: sessionId ?? this.sessionId,
      peerIp: peerIp ?? this.peerIp,
      peerDeviceId: peerDeviceId ?? this.peerDeviceId,
      mode: mode ?? this.mode,
      startedAt: startedAt ?? this.startedAt,
      connectionState: connectionState ?? this.connectionState,
      disconnectCount: disconnectCount ?? this.disconnectCount,
      totalDisconnectDuration:
          totalDisconnectDuration ?? this.totalDisconnectDuration,
    );
  }

  String get stateKey {
    switch (connectionState) {
      case ConnectionState.connected:
        return 'CONNECTED';
      case ConnectionState.reconnectingNetwork:
        return 'RECONNECTING_NETWORK';
      case ConnectionState.reconnectingPeer:
        return 'RECONNECTING_PEER';
      case ConnectionState.suspended:
        return 'SUSPENDED';
      case ConnectionState.disconnected:
        return 'DISCONNECTED';
    }
  }
}
