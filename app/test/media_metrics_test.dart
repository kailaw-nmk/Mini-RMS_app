import 'package:flutter_test/flutter_test.dart';
import 'package:tailcall/features/metrics/media_metrics.dart';

void main() {
  group('MediaMetrics quality assessment', () {
    test('EXCELLENT: low RTT, low loss, low jitter', () {
      const m = MediaMetrics(rtt: 50, packetLoss: 0.005, jitter: 10);
      expect(m.qualityLevel, QualityLevel.excellent);
      expect(m.recommendedBitrate, 32000);
      expect(m.qualityDisplayName, '最高');
      expect(m.qualityNormalized, 1.0);
    });

    test('GOOD: moderate RTT, low loss', () {
      const m = MediaMetrics(rtt: 150, packetLoss: 0.02, jitter: 20);
      expect(m.qualityLevel, QualityLevel.good);
      expect(m.recommendedBitrate, 24000);
      expect(m.qualityDisplayName, '良好');
    });

    test('FAIR: high RTT, moderate loss', () {
      const m = MediaMetrics(rtt: 300, packetLoss: 0.06, jitter: 50);
      expect(m.qualityLevel, QualityLevel.fair);
      expect(m.recommendedBitrate, 16000);
      expect(m.qualityDisplayName, '普通');
    });

    test('POOR: very high RTT, high loss', () {
      const m = MediaMetrics(rtt: 600, packetLoss: 0.15, jitter: 150);
      expect(m.qualityLevel, QualityLevel.poor);
      expect(m.recommendedBitrate, 16000);
      expect(m.qualityDisplayName, '低品質');
    });

    test('CRITICAL: packet silence > 5 seconds', () {
      const m = MediaMetrics(
        rtt: 50,
        packetLoss: 0.0,
        jitter: 10,
        lastPacketReceivedAge: Duration(seconds: 6),
      );
      expect(m.qualityLevel, QualityLevel.critical);
      expect(m.qualityDisplayName, '通信断');
      expect(m.qualityNormalized, 0.0);
    });

    test('CRITICAL overrides good metrics when packets silent', () {
      const m = MediaMetrics(
        rtt: 10, // excellent RTT
        packetLoss: 0.0, // no loss
        jitter: 5, // low jitter
        lastPacketReceivedAge: Duration(seconds: 10), // but no packets!
      );
      expect(m.qualityLevel, QualityLevel.critical);
    });

    test('boundary: exactly 5 seconds is not critical', () {
      const m = MediaMetrics(
        rtt: 50,
        lastPacketReceivedAge: Duration(seconds: 5),
      );
      expect(m.qualityLevel, isNot(QualityLevel.critical));
    });

    test('toJson outputs correct format', () {
      const m = MediaMetrics(
        rtt: 145,
        jitter: 23,
        packetLoss: 0.02,
        availableBandwidth: 1200000,
      );
      final json = m.toJson();
      expect(json['rtt_ms'], 145);
      expect(json['jitter_ms'], 23);
      expect(json['packet_loss'], 0.02);
      expect(json['bandwidth_bps'], 1200000);
      expect(json['quality_level'], 'GOOD');
    });

    test('default metrics have zero values', () {
      const m = MediaMetrics();
      expect(m.rtt, 0);
      expect(m.jitter, 0);
      expect(m.packetLoss, 0);
      expect(m.qualityLevel, QualityLevel.excellent);
    });
  });

  group('QualityLevel', () {
    test('has 5 levels', () {
      expect(QualityLevel.values, hasLength(5));
    });

    test('scoring boundaries', () {
      // Score >= 7: EXCELLENT (RTT<100=3, Loss<1%=3, Jitter<30=2 => 8)
      const excellent = MediaMetrics(rtt: 50, packetLoss: 0.005, jitter: 20);
      expect(excellent.qualityLevel, QualityLevel.excellent);

      // Score 5-6: GOOD (RTT<200=2, Loss<5%=2, Jitter<30=2 => 6)
      const good = MediaMetrics(rtt: 150, packetLoss: 0.03, jitter: 25);
      expect(good.qualityLevel, QualityLevel.good);

      // Score 3-4: FAIR (RTT<500=1, Loss<10%=1, Jitter<100=1 => 3)
      const fair = MediaMetrics(rtt: 400, packetLoss: 0.08, jitter: 80);
      expect(fair.qualityLevel, QualityLevel.fair);

      // Score 0-2: POOR (RTT>500=0, Loss>10%=0, Jitter>100=0 => 0)
      const poor = MediaMetrics(rtt: 800, packetLoss: 0.2, jitter: 200);
      expect(poor.qualityLevel, QualityLevel.poor);
    });
  });
}
