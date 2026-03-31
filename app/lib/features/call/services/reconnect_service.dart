import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/call_state.dart';
import 'connection_state_machine.dart';
import 'signaling_client.dart';
import 'sdp_utils.dart';

/// Configuration for reconnect behavior
class ReconnectConfig {
  final Duration iceRestartTimeout;
  final int maxIceRestartAttempts;
  final Duration pcRecreateTimeout;
  final Duration initialBackoff;
  final Duration maxBackoff;
  final Duration suspendedThreshold;
  final Duration sessionExpireThreshold;
  final Duration suspendedRetryInterval;

  const ReconnectConfig({
    this.iceRestartTimeout = const Duration(seconds: 5),
    this.maxIceRestartAttempts = 2,
    this.pcRecreateTimeout = const Duration(seconds: 10),
    this.initialBackoff = const Duration(milliseconds: 500),
    this.maxBackoff = const Duration(seconds: 30),
    this.suspendedThreshold = const Duration(minutes: 5),
    this.sessionExpireThreshold = const Duration(minutes: 30),
    this.suspendedRetryInterval = const Duration(seconds: 30),
  });
}

/// Reconnect strategy result
enum ReconnectResult {
  success,
  iceRestartFailed,
  pcRecreateFailed,
  sessionExpired,
  cancelled,
}

/// Auto-reconnect service implementing graduated fallback strategy
/// ICE Restart (max 2) -> PeerConnection recreation -> exponential backoff
class ReconnectService {
  final ConnectionStateMachine stateMachine;
  final SignalingClient signaling;
  final ReconnectConfig config;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  String? _sessionId;
  String? _lastLocalIp;

  int _iceRestartFailCount = 0;
  int _backoffStep = 0;
  bool _isReconnecting = false;
  bool _cancelled = false;
  Timer? _backoffTimer;
  Timer? _suspendedCheckTimer;
  Completer<bool>? _iceConnectedCompleter;

  final _reconnectResultController =
      StreamController<ReconnectResult>.broadcast();
  final _ipChangeController = StreamController<String>.broadcast();

  ReconnectService({
    required this.stateMachine,
    required this.signaling,
    this.config = const ReconnectConfig(),
  });

  /// Stream of reconnect results
  Stream<ReconnectResult> get onReconnectResult =>
      _reconnectResultController.stream;

  /// Stream of IP change events
  Stream<String> get onIpChange => _ipChangeController.stream;

  /// Whether reconnection is in progress
  bool get isReconnecting => _isReconnecting;

  /// Current ICE restart fail count
  int get iceRestartFailCount => _iceRestartFailCount;

  /// Set the active PeerConnection and local stream
  void setConnectionContext({
    required RTCPeerConnection peerConnection,
    required MediaStream localStream,
    required String sessionId,
    String? localIp,
  }) {
    _peerConnection = peerConnection;
    _localStream = localStream;
    _sessionId = sessionId;
    _lastLocalIp = localIp;
  }

  /// Start the reconnect process
  Future<ReconnectResult> startReconnect({String? currentLocalIp}) async {
    if (_isReconnecting) return ReconnectResult.cancelled;
    _isReconnecting = true;
    _cancelled = false;
    _iceRestartFailCount = 0;
    _backoffStep = 0;

    debugPrint('Reconnect: starting reconnect process');

    // Start SUSPENDED/DISCONNECTED check timer
    _startSuspendedCheckTimer();

    try {
      // Check IP change
      final ipChanged =
          currentLocalIp != null && currentLocalIp != _lastLocalIp;
      if (ipChanged) {
        debugPrint(
            'Reconnect: IP changed $_lastLocalIp -> $currentLocalIp, skip ICE Restart');
        _lastLocalIp = currentLocalIp;
        _ipChangeController.add(currentLocalIp);
        return await _attemptPcRecreate();
      }

      // Normal flow: ICE Restart first
      return await _reconnectLoop();
    } finally {
      _isReconnecting = false;
      _suspendedCheckTimer?.cancel();
    }
  }

  Future<ReconnectResult> _reconnectLoop() async {
    while (!_cancelled) {
      // Check session expiry
      if (stateMachine.shouldSessionExpire()) {
        stateMachine.transitionTo(ConnectionState.disconnected);
        _reconnectResultController.add(ReconnectResult.sessionExpired);
        return ReconnectResult.sessionExpired;
      }

      // Try ICE Restart (max 2 attempts)
      if (_iceRestartFailCount < config.maxIceRestartAttempts) {
        final iceResult = await _attemptIceRestart();
        if (iceResult == ReconnectResult.success) return iceResult;
        _iceRestartFailCount++;
        debugPrint(
            'Reconnect: ICE Restart failed ($_iceRestartFailCount/${config.maxIceRestartAttempts})');

        if (_iceRestartFailCount < config.maxIceRestartAttempts) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
      }

      // ICE Restart exhausted -> PeerConnection recreation
      final pcResult = await _attemptPcRecreate();
      if (pcResult == ReconnectResult.success) return pcResult;

      // PC recreation failed -> exponential backoff and retry
      final backoffDuration = _calculateBackoff();
      debugPrint(
          'Reconnect: backoff ${backoffDuration.inMilliseconds}ms (step $_backoffStep)');

      await _waitWithCancellation(backoffDuration);
      if (_cancelled) return ReconnectResult.cancelled;

      // Reset ICE restart count for next cycle
      _iceRestartFailCount = 0;
      _backoffStep++;
    }

    return ReconnectResult.cancelled;
  }

  /// Attempt ICE Restart
  Future<ReconnectResult> _attemptIceRestart() async {
    if (_peerConnection == null || _sessionId == null) {
      return ReconnectResult.iceRestartFailed;
    }

    debugPrint('Reconnect: attempting ICE Restart');

    try {
      final offer = await _peerConnection!.createOffer({
        'iceRestart': true,
      });

      final optimizedSdp =
          SdpUtils.applyOpusOptimizations(offer.sdp!, bitrate: 24000);
      await _peerConnection!
          .setLocalDescription(RTCSessionDescription(optimizedSdp, 'offer'));

      signaling.sendOffer(_sessionId!, optimizedSdp, iceRestart: true);

      // Wait for ICE connected state
      final connected = await _waitForIceConnected(config.iceRestartTimeout);
      if (connected) {
        _onReconnectSuccess();
        return ReconnectResult.success;
      }

      return ReconnectResult.iceRestartFailed;
    } catch (e) {
      debugPrint('Reconnect: ICE Restart error: $e');
      return ReconnectResult.iceRestartFailed;
    }
  }

  /// Attempt PeerConnection recreation
  Future<ReconnectResult> _attemptPcRecreate() async {
    if (_localStream == null || _sessionId == null) {
      return ReconnectResult.pcRecreateFailed;
    }

    debugPrint('Reconnect: attempting PeerConnection recreation');

    try {
      // 1. Close old PeerConnection
      await _peerConnection?.close();

      // 2. Create new PeerConnection
      _peerConnection = await createPeerConnection({
        'iceServers': <Map<String, dynamic>>[],
        'sdpSemantics': 'unified-plan',
      });

      // 3. Re-attach media tracks
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      // 4. Set up ICE candidate handler
      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null) {
          signaling.sendIceCandidate(
            _sessionId!,
            candidate.candidate!,
            candidate.sdpMid ?? '0',
            candidate.sdpMLineIndex ?? 0,
          );
        }
      };

      // 5. Set up ICE state handler
      _peerConnection!.onIceConnectionState = (state) {
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _iceConnectedCompleter?.complete(true);
        }
      };

      // 6. Create and send new offer
      final offer = await _peerConnection!.createOffer();
      final optimizedSdp =
          SdpUtils.applyOpusOptimizations(offer.sdp!, bitrate: 24000);
      await _peerConnection!
          .setLocalDescription(RTCSessionDescription(optimizedSdp, 'offer'));

      // Send pc_recreate message
      signaling.send({
        'type': 'pc_recreate',
        'session_id': _sessionId,
        'reason': _iceRestartFailCount >= config.maxIceRestartAttempts
            ? 'ice_restart_failed_twice'
            : 'ip_changed',
        'new_sdp_offer': optimizedSdp,
      });

      // 7. Wait for ICE connected
      final connected = await _waitForIceConnected(config.pcRecreateTimeout);
      if (connected) {
        _onReconnectSuccess();
        return ReconnectResult.success;
      }

      return ReconnectResult.pcRecreateFailed;
    } catch (e) {
      debugPrint('Reconnect: PC recreation error: $e');
      return ReconnectResult.pcRecreateFailed;
    }
  }

  void _onReconnectSuccess() {
    debugPrint('Reconnect: SUCCESS');
    _iceRestartFailCount = 0;
    _backoffStep = 0;
    stateMachine.transitionTo(ConnectionState.connected);
    _reconnectResultController.add(ReconnectResult.success);
  }

  Future<bool> _waitForIceConnected(Duration timeout) async {
    _iceConnectedCompleter = Completer<bool>();

    // Listen for ICE state from existing PC
    _peerConnection?.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        if (!_iceConnectedCompleter!.isCompleted) {
          _iceConnectedCompleter!.complete(true);
        }
      }
    };

    try {
      return await _iceConnectedCompleter!.future
          .timeout(timeout, onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  Duration _calculateBackoff() {
    final ms = config.initialBackoff.inMilliseconds *
        pow(2, _backoffStep.clamp(0, 10));
    final clamped = ms.clamp(
      config.initialBackoff.inMilliseconds,
      config.maxBackoff.inMilliseconds,
    );
    return Duration(milliseconds: clamped.toInt());
  }

  Future<void> _waitWithCancellation(Duration duration) async {
    final completer = Completer<void>();
    _backoffTimer = Timer(duration, () {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
  }

  void _startSuspendedCheckTimer() {
    _suspendedCheckTimer?.cancel();
    _suspendedCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (stateMachine.shouldSessionExpire()) {
        stateMachine.transitionTo(ConnectionState.disconnected);
        cancel();
      } else if (stateMachine.shouldTransitionToSuspended()) {
        stateMachine.transitionTo(ConnectionState.suspended);
      }
    });
  }

  /// Cancel the reconnect process
  void cancel() {
    _cancelled = true;
    _backoffTimer?.cancel();
    _suspendedCheckTimer?.cancel();
    if (_iceConnectedCompleter != null && !_iceConnectedCompleter!.isCompleted) {
      _iceConnectedCompleter!.complete(false);
    }
  }

  /// Get the recreated PeerConnection (after PC recreation)
  RTCPeerConnection? get peerConnection => _peerConnection;

  void dispose() {
    cancel();
    _reconnectResultController.close();
    _ipChangeController.close();
  }
}
