import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';

/// WebSocket signaling client for SDP/ICE exchange
class SignalingClient {
  final String url;
  final String deviceToken;
  final String deviceId;

  WebSocketChannel? _channel;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  bool _disposed = false;
  String? _sessionResumeId;

  SignalingClient({
    required this.url,
    required this.deviceToken,
    required this.deviceId,
    String? sessionResumeId,
  }) : _sessionResumeId = sessionResumeId;

  /// Stream of incoming messages
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// Whether the WebSocket is connected
  bool get isConnected => _channel != null;

  /// Connect to the signaling server
  Future<void> connect() async {
    if (_disposed) return;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      await _channel!.ready;

      // Send auth message immediately
      send({
        'type': 'auth',
        'device_token': deviceToken,
        'device_id': deviceId,
        'session_resume_id': _sessionResumeId,
      });

      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            _messageController.add(msg);
          } catch (e) {
            debugPrint('Signaling: failed to parse message: $e');
          }
        },
        onDone: () {
          debugPrint('Signaling: WebSocket closed');
          _channel = null;
        },
        onError: (error) {
          debugPrint('Signaling: WebSocket error: $error');
          _channel = null;
        },
      );

      debugPrint('Signaling: connected to $url');
    } catch (e) {
      debugPrint('Signaling: connection failed: $e');
      _channel = null;
      rethrow;
    }
  }

  /// Send a JSON message
  void send(Map<String, dynamic> message) {
    if (_channel == null) {
      debugPrint('Signaling: cannot send, not connected');
      return;
    }
    _channel!.sink.add(jsonEncode(message));
  }

  /// Send SDP offer
  void sendOffer(String sessionId, String sdp, {bool iceRestart = false}) {
    send({
      'type': 'sdp_offer',
      'session_id': sessionId,
      'sdp': sdp,
      'ice_restart': iceRestart,
      'reconnect_strategy': iceRestart ? 'ice_restart' : 'initial',
    });
  }

  /// Send SDP answer
  void sendAnswer(String sessionId, String sdp) {
    send({
      'type': 'sdp_answer',
      'session_id': sessionId,
      'sdp': sdp,
    });
  }

  /// Send ICE candidate
  void sendIceCandidate(
      String sessionId, String candidate, String sdpMid, int sdpMLineIndex) {
    send({
      'type': 'ice_candidate',
      'session_id': sessionId,
      'candidate': {
        'candidate': candidate,
        'sdpMid': sdpMid,
        'sdpMLineIndex': sdpMLineIndex,
      },
    });
  }

  /// Initiate a call (operator only)
  void initiateCall(String fromIp, String toIp, {String mode = 'audio'}) {
    send({
      'type': 'call_initiate',
      'from': fromIp,
      'to': toIp,
      'mode': mode,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// End a call
  void endCall(String sessionId, {String reason = 'operator_hangup'}) {
    send({
      'type': 'call_end',
      'session_id': sessionId,
      'reason': reason,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Set session ID for resume on reconnect
  set sessionResumeId(String? id) => _sessionResumeId = id;

  /// Disconnect
  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
  }

  /// Dispose resources
  void dispose() {
    _disposed = true;
    disconnect();
    _messageController.close();
  }
}
