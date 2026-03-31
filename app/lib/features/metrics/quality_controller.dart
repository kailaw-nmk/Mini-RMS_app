import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'media_metrics.dart';

/// Callback for video auto-control based on quality
typedef VideoAutoControlCallback = void Function(bool shouldEnableVideo);

/// Monitors RTP/RTCP stats and adjusts audio/video quality dynamically
class QualityController {
  RTCPeerConnection? _peerConnection;
  Timer? _pollTimer;
  DateTime? _lastPacketTime;

  MediaMetrics _currentMetrics = const MediaMetrics();
  QualityLevel _lastLevel = QualityLevel.good;
  int _hysteresisCount = 0;
  static const int _hysteresisThreshold = 3; // Require 3 consecutive readings

  /// Callback to auto-disable video when quality drops
  VideoAutoControlCallback? onVideoAutoControl;

  final _metricsController = StreamController<MediaMetrics>.broadcast();
  final _qualityChangeController = StreamController<QualityLevel>.broadcast();

  /// Stream of collected metrics (every 2 seconds)
  Stream<MediaMetrics> get onMetrics => _metricsController.stream;

  /// Stream of quality level changes (only fires when level changes)
  Stream<QualityLevel> get onQualityChange => _qualityChangeController.stream;

  /// Current metrics snapshot
  MediaMetrics get currentMetrics => _currentMetrics;

  /// Start monitoring with the given PeerConnection
  void start(RTCPeerConnection pc) {
    _peerConnection = pc;
    _lastPacketTime = DateTime.now();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    debugPrint('QualityController: started');
  }

  /// Stop monitoring
  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _peerConnection = null;
    debugPrint('QualityController: stopped');
  }

  Future<void> _poll() async {
    if (_peerConnection == null) return;

    try {
      final stats = await _peerConnection!.getStats();

      double rtt = 0;
      double jitter = 0;
      double packetLoss = 0;
      int bandwidth = 0;
      int packetsReceived = 0;
      int packetsLost = 0;

      for (final report in stats) {
        // Inbound RTP stats (audio)
        if (report.type == 'inbound-rtp' &&
            report.values['kind'] == 'audio') {
          packetsReceived =
              (report.values['packetsReceived'] as int?) ?? 0;
          packetsLost = (report.values['packetsLost'] as int?) ?? 0;
          jitter = ((report.values['jitter'] as double?) ?? 0.0) * 1000;

          if (packetsReceived > 0) {
            _lastPacketTime = DateTime.now();
          }
        }

        // Candidate pair stats
        if (report.type == 'candidate-pair' &&
            report.values['state'] == 'succeeded') {
          rtt = ((report.values['currentRoundTripTime'] as double?) ?? 0.0) *
              1000;
          bandwidth =
              (report.values['availableOutgoingBitrate'] as int?) ?? 0;
        }
      }

      // Calculate packet loss ratio
      final totalPackets = packetsReceived + packetsLost;
      packetLoss = totalPackets > 0 ? packetsLost / totalPackets : 0;

      final age = _lastPacketTime != null
          ? DateTime.now().difference(_lastPacketTime!)
          : Duration.zero;

      _currentMetrics = MediaMetrics(
        rtt: rtt,
        jitter: jitter,
        packetLoss: packetLoss,
        availableBandwidth: bandwidth,
        lastPacketReceivedAge: age,
      );

      _metricsController.add(_currentMetrics);

      // Check for quality level change with hysteresis
      final newLevel = _currentMetrics.qualityLevel;
      if (newLevel != _lastLevel) {
        _hysteresisCount++;
        // Require multiple consecutive readings to avoid rapid oscillation
        if (_hysteresisCount >= _hysteresisThreshold ||
            newLevel == QualityLevel.critical) {
          _lastLevel = newLevel;
          _hysteresisCount = 0;
          _qualityChangeController.add(newLevel);
          debugPrint('QualityController: level changed to ${newLevel.name}');
          _applyQualityAdjustment(newLevel);

          // Auto-disable video on FAIR or worse
          if (newLevel.index >= QualityLevel.fair.index) {
            onVideoAutoControl?.call(false);
          }
        }
      } else {
        _hysteresisCount = 0;
      }
    } catch (e) {
      debugPrint('QualityController: poll error: $e');
    }
  }

  /// Adjust Opus bitrate based on quality level
  Future<void> _applyQualityAdjustment(QualityLevel level) async {
    if (_peerConnection == null) return;

    final targetBitrate = _currentMetrics.recommendedBitrate;

    try {
      final senders = await _peerConnection!.senders;
      for (final sender in senders) {
        if (sender.track?.kind == 'audio') {
          final params = sender.parameters;
          if (params.encodings != null && params.encodings!.isNotEmpty) {
            params.encodings![0].maxBitrate = targetBitrate;
            sender.setParameters(params);
            debugPrint(
                'QualityController: set audio bitrate to $targetBitrate');
          }
        }
      }
    } catch (e) {
      debugPrint('QualityController: failed to set bitrate: $e');
    }
  }

  void dispose() {
    stop();
    _metricsController.close();
    _qualityChangeController.close();
  }
}
