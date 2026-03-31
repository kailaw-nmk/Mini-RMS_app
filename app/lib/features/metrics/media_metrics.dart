/// Quality level enumeration
enum QualityLevel { excellent, good, fair, poor, critical }

/// Collected RTP/RTCP media metrics
class MediaMetrics {
  final double rtt; // Round Trip Time (ms)
  final double jitter; // Packet arrival jitter (ms)
  final double packetLoss; // Packet loss ratio (0.0 - 1.0)
  final int availableBandwidth; // Estimated bandwidth (bps)
  final Duration lastPacketReceivedAge; // Since last packet
  final int nackCount; // NACK requests (video quality)
  final int firCount; // FIR requests (keyframe)

  const MediaMetrics({
    this.rtt = 0,
    this.jitter = 0,
    this.packetLoss = 0,
    this.availableBandwidth = 0,
    this.lastPacketReceivedAge = Duration.zero,
    this.nackCount = 0,
    this.firCount = 0,
  });

  /// Assess quality level based on weighted scoring
  QualityLevel get qualityLevel {
    // Packet silence > 5s = critical
    if (lastPacketReceivedAge > const Duration(seconds: 5)) {
      return QualityLevel.critical;
    }

    // Weighted score calculation
    double score = 0;
    score += (rtt < 100) ? 3 : (rtt < 200) ? 2 : (rtt < 500) ? 1 : 0;
    score += (packetLoss < 0.01)
        ? 3
        : (packetLoss < 0.05)
            ? 2
            : (packetLoss < 0.1)
                ? 1
                : 0;
    score += (jitter < 30) ? 2 : (jitter < 100) ? 1 : 0;

    if (score >= 7) return QualityLevel.excellent;
    if (score >= 5) return QualityLevel.good;
    if (score >= 3) return QualityLevel.fair;
    return QualityLevel.poor;
  }

  /// Recommended Opus bitrate for current quality level
  int get recommendedBitrate {
    switch (qualityLevel) {
      case QualityLevel.excellent:
        return 32000;
      case QualityLevel.good:
        return 24000;
      case QualityLevel.fair:
      case QualityLevel.poor:
        return 16000;
      case QualityLevel.critical:
        return 16000;
    }
  }

  /// Quality display name (Japanese)
  String get qualityDisplayName {
    switch (qualityLevel) {
      case QualityLevel.excellent:
        return '最高';
      case QualityLevel.good:
        return '良好';
      case QualityLevel.fair:
        return '普通';
      case QualityLevel.poor:
        return '低品質';
      case QualityLevel.critical:
        return '通信断';
    }
  }

  /// Quality as a normalized value (0.0 - 1.0) for progress bars
  double get qualityNormalized {
    switch (qualityLevel) {
      case QualityLevel.excellent:
        return 1.0;
      case QualityLevel.good:
        return 0.75;
      case QualityLevel.fair:
        return 0.5;
      case QualityLevel.poor:
        return 0.25;
      case QualityLevel.critical:
        return 0.0;
    }
  }

  Map<String, dynamic> toJson() => {
        'rtt_ms': rtt,
        'jitter_ms': jitter,
        'packet_loss': packetLoss,
        'bandwidth_bps': availableBandwidth,
        'quality_level': qualityLevel.name.toUpperCase(),
      };
}
