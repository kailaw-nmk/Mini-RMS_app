import 'package:flutter/material.dart';
import '../models/call_state.dart' as app;
import '../../../core/constants.dart';

class CallStatusBar extends StatelessWidget {
  final app.ConnectionState connectionState;
  final Duration callDuration;

  const CallStatusBar({
    super.key,
    required this.connectionState,
    required this.callDuration,
  });

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _stateEmoji(app.ConnectionState state) {
    switch (state) {
      case app.ConnectionState.connected:
        return '🟢';
      case app.ConnectionState.reconnectingNetwork:
      case app.ConnectionState.reconnectingPeer:
        return '🟡';
      case app.ConnectionState.suspended:
        return '🟠';
      case app.ConnectionState.disconnected:
        return '⚪';
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateKey = connectionState == app.ConnectionState.connected
        ? 'CONNECTED'
        : connectionState == app.ConnectionState.reconnectingNetwork
            ? 'RECONNECTING_NETWORK'
            : connectionState == app.ConnectionState.reconnectingPeer
                ? 'RECONNECTING_PEER'
                : connectionState == app.ConnectionState.suspended
                    ? 'SUSPENDED'
                    : 'DISCONNECTED';

    final color = Color(kStateColors[stateKey] ?? 0xFF9E9E9E);
    final displayName = kStateDisplayNames[stateKey] ?? stateKey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border(bottom: BorderSide(color: color, width: 2)),
      ),
      child: Row(
        children: [
          Text(_stateEmoji(connectionState), style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(
            displayName,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const Spacer(),
          Text(
            _formatDuration(callDuration),
            style: const TextStyle(
              fontSize: 18,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
