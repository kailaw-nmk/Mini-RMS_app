import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Aggregated network status from all 4 detection layers
enum NetworkStatus {
  online, // All layers indicate connectivity
  degraded, // Some layers indicate issues
  offline, // Network is unavailable
}

/// 4-Layer network detection system
/// Priority: Layer 4 (RTP) > Layer 3 (ICE) > Layer 1 (OS) > Layer 2 (Tailscale)
class NetworkMonitor {
  // Layer 1: OS network state
  bool _osOnline = true;

  // Layer 2: Tailscale peer state (reference only, lowest priority)
  // ignore: unused_field - used in _evaluateStatus via updateTailscalePeerState
  bool _tailscalePeerOnline = true;

  // Layer 3: ICE connection state
  RTCIceConnectionState _iceState =
      RTCIceConnectionState.RTCIceConnectionStateNew;

  // Layer 4: RTP/RTCP metrics (highest priority)
  DateTime? _lastPacketReceived;
  double _packetLoss = 0.0;
  double _rtt = 0.0;

  Timer? _metricsTimer;
  RTCPeerConnection? _peerConnection;

  final _statusController = StreamController<NetworkStatus>.broadcast();
  final _rtpSilenceController = StreamController<bool>.broadcast();

  /// Stream of overall network status changes
  Stream<NetworkStatus> get onStatusChange => _statusController.stream;

  /// Stream of RTP silence events (true = silence detected > 5s)
  Stream<bool> get onRtpSilence => _rtpSilenceController.stream;

  // -- Layer 1: OS Network --

  void updateOsNetworkState(bool isOnline) {
    _osOnline = isOnline;
    debugPrint('NetworkMonitor L1: OS ${isOnline ? "online" : "offline"}');
    _evaluateStatus();
  }

  // -- Layer 2: Tailscale Peer --

  void updateTailscalePeerState(bool isOnline) {
    _tailscalePeerOnline = isOnline;
    debugPrint(
        'NetworkMonitor L2: Tailscale peer ${isOnline ? "online" : "offline"}');
    _evaluateStatus();
  }

  // -- Layer 3: ICE State --

  void updateIceState(RTCIceConnectionState state) {
    _iceState = state;
    debugPrint('NetworkMonitor L3: ICE $state');
    _evaluateStatus();
  }

  // -- Layer 4: RTP/RTCP Metrics --

  /// Start periodic metrics polling from PeerConnection
  void startMetricsPolling(RTCPeerConnection pc) {
    _peerConnection = pc;
    _lastPacketReceived = DateTime.now();
    _metricsTimer?.cancel();
    _metricsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollMetrics();
    });
  }

  void stopMetricsPolling() {
    _metricsTimer?.cancel();
    _metricsTimer = null;
    _peerConnection = null;
  }

  Future<void> _pollMetrics() async {
    if (_peerConnection == null) return;

    try {
      final stats = await _peerConnection!.getStats();
      for (final report in stats) {
        if (report.type == 'inbound-rtp' && report.values['kind'] == 'audio') {
          final packetsReceived = report.values['packetsReceived'] as int? ?? 0;
          final packetsLost = report.values['packetsLost'] as int? ?? 0;
          final total = packetsReceived + packetsLost;
          _packetLoss = total > 0 ? packetsLost / total : 0.0;

          if (packetsReceived > 0) {
            _lastPacketReceived = DateTime.now();
          }
        }

        if (report.type == 'candidate-pair' &&
            report.values['state'] == 'succeeded') {
          _rtt = (report.values['currentRoundTripTime'] as double? ?? 0.0) *
              1000; // to ms
        }
      }

      // Check RTP silence (no packets for > 5 seconds)
      if (_lastPacketReceived != null) {
        final silence = DateTime.now().difference(_lastPacketReceived!);
        if (silence > const Duration(seconds: 5)) {
          debugPrint('NetworkMonitor L4: RTP silence ${silence.inSeconds}s');
          _rtpSilenceController.add(true);
        }
      }

      _evaluateStatus();
    } catch (e) {
      debugPrint('NetworkMonitor: metrics poll error: $e');
    }
  }

  /// Current packet loss ratio
  double get packetLoss => _packetLoss;

  /// Current RTT in milliseconds
  double get rtt => _rtt;

  /// Duration since last packet received
  Duration? get lastPacketAge {
    if (_lastPacketReceived == null) return null;
    return DateTime.now().difference(_lastPacketReceived!);
  }

  // -- Status Evaluation --

  /// Evaluate overall network status based on 4-layer priority
  void _evaluateStatus() {
    NetworkStatus status;

    // Priority 1: Layer 4 - RTP silence means effectively offline
    if (_lastPacketReceived != null &&
        DateTime.now().difference(_lastPacketReceived!) >
            const Duration(seconds: 5)) {
      status = NetworkStatus.offline;
    }
    // Priority 2: Layer 3 - ICE failed/disconnected
    else if (_iceState ==
            RTCIceConnectionState.RTCIceConnectionStateFailed ||
        _iceState ==
            RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
      status = NetworkStatus.offline;
    }
    // Priority 3: Layer 1 - OS says offline
    else if (!_osOnline) {
      status = NetworkStatus.offline;
    }
    // High packet loss = degraded
    else if (_packetLoss > 0.1) {
      status = NetworkStatus.degraded;
    }
    // Everything looks good
    else {
      status = NetworkStatus.online;
    }

    _statusController.add(status);
  }

  void dispose() {
    _metricsTimer?.cancel();
    _statusController.close();
    _rtpSilenceController.close();
  }
}
