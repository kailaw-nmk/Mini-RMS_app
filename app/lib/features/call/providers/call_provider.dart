import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/call_state.dart' as app;
import '../services/signaling_client.dart';
import '../services/webrtc_service.dart';

/// State for the active call
class CallState {
  final app.CallSession? session;
  final bool isMuted;
  final bool isConnecting;
  final String? error;
  final MediaStream? remoteStream;

  const CallState({
    this.session,
    this.isMuted = false,
    this.isConnecting = false,
    this.error,
    this.remoteStream,
  });

  CallState copyWith({
    app.CallSession? session,
    bool? isMuted,
    bool? isConnecting,
    String? error,
    MediaStream? remoteStream,
    bool clearSession = false,
    bool clearError = false,
    bool clearRemoteStream = false,
  }) {
    return CallState(
      session: clearSession ? null : (session ?? this.session),
      isMuted: isMuted ?? this.isMuted,
      isConnecting: isConnecting ?? this.isConnecting,
      error: clearError ? null : (error ?? this.error),
      remoteStream:
          clearRemoteStream ? null : (remoteStream ?? this.remoteStream),
    );
  }
}

/// Call notifier managing WebRTC + signaling lifecycle
class CallNotifier extends Notifier<CallState> {
  SignalingClient? _signaling;
  WebRTCService? _webrtc;
  StreamSubscription? _remoteStreamSub;
  StreamSubscription? _iceStateSub;
  Timer? _durationTimer;
  DateTime? _callStartTime;

  @override
  CallState build() => const CallState();

  /// Initialize signaling connection
  Future<void> connect({
    required String serverUrl,
    required String deviceToken,
    required String deviceId,
  }) async {
    _signaling = SignalingClient(
      url: serverUrl,
      deviceToken: deviceToken,
      deviceId: deviceId,
    );

    _webrtc = WebRTCService(signaling: _signaling!);

    _remoteStreamSub = _webrtc!.onRemoteStream.listen((stream) {
      if (stream == null) {
        state = state.copyWith(clearRemoteStream: true);
      } else {
        state = state.copyWith(remoteStream: stream);
      }
    });

    _iceStateSub = _webrtc!.onIceStateChange.listen(_onIceStateChange);

    try {
      await _signaling!.connect();
      state = state.copyWith(clearError: true);
    } catch (e) {
      state = state.copyWith(error: 'サーバーに接続できません: $e');
    }
  }

  void _onIceStateChange(RTCIceConnectionState iceState) {
    if (state.session == null) return;

    app.ConnectionState newState;
    switch (iceState) {
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        newState = app.ConnectionState.connected;
        _startDurationTimer();
        break;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        newState = app.ConnectionState.reconnectingNetwork;
        break;
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        newState = app.ConnectionState.reconnectingNetwork;
        break;
      case RTCIceConnectionState.RTCIceConnectionStateClosed:
        newState = app.ConnectionState.disconnected;
        _durationTimer?.cancel();
        break;
      default:
        return;
    }

    state = state.copyWith(
      session: state.session!.copyWith(connectionState: newState),
    );
  }

  void _startDurationTimer() {
    _callStartTime ??= DateTime.now();
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.session != null) {
        state = state.copyWith();
      }
    });
  }

  /// Start a call (operator role)
  Future<void> startCall(String fromIp, String toIp) async {
    state = state.copyWith(isConnecting: true, clearError: true);
    try {
      await _webrtc!.startCall(fromIp, toIp);
      _callStartTime = DateTime.now();
      state = state.copyWith(
        isConnecting: false,
        session: app.CallSession(
          sessionId: _webrtc!.sessionId!,
          peerIp: toIp,
          startedAt: _callStartTime!,
          connectionState: app.ConnectionState.connected,
        ),
      );
      _startDurationTimer();
    } catch (e) {
      state = state.copyWith(
        isConnecting: false,
        error: '通話開始に失敗しました: $e',
      );
    }
  }

  /// Toggle mute
  void toggleMute() {
    _webrtc?.toggleMute();
    state = state.copyWith(isMuted: _webrtc?.isMuted ?? false);
  }

  /// End the call
  Future<void> endCall() async {
    _durationTimer?.cancel();
    await _webrtc?.hangUp();
    _callStartTime = null;
    state = state.copyWith(
      clearSession: true,
      clearRemoteStream: true,
      isMuted: false,
    );
  }

  /// Current call duration
  Duration get callDuration {
    if (_callStartTime == null) return Duration.zero;
    return DateTime.now().difference(_callStartTime!);
  }

  /// Clean up resources
  void cleanup() {
    _durationTimer?.cancel();
    _remoteStreamSub?.cancel();
    _iceStateSub?.cancel();
    _webrtc?.dispose();
    _signaling?.dispose();
  }
}

/// Provider for call state
final callProvider =
    NotifierProvider<CallNotifier, CallState>(CallNotifier.new);
