import 'package:flutter_test/flutter_test.dart';
import 'package:tailcall/features/session/session_cache.dart';

void main() {
  group('CachedSession', () {
    test('serializes to JSON', () {
      final session = CachedSession(
        sessionId: 'sess_001',
        peerTailscaleIp: '100.64.0.5',
        lastSdpOffer: 'v=0...',
        lastSdpAnswer: 'v=0...',
        deviceToken: 'eyJhbGci...',
        cachedAt: DateTime.utc(2026, 3, 28, 9, 15),
      );

      final json = session.toJson();
      expect(json['session_id'], 'sess_001');
      expect(json['peer_tailscale_ip'], '100.64.0.5');
      expect(json['last_sdp_offer'], 'v=0...');
      expect(json['device_token'], 'eyJhbGci...');
      expect(json['cached_at'], '2026-03-28T09:15:00.000Z');
    });

    test('deserializes from JSON', () {
      final json = {
        'session_id': 'sess_002',
        'peer_tailscale_ip': '100.64.0.12',
        'last_sdp_offer': null,
        'last_sdp_answer': null,
        'device_token': 'token123',
        'cached_at': '2026-03-28T10:00:00.000Z',
      };

      final session = CachedSession.fromJson(json);
      expect(session.sessionId, 'sess_002');
      expect(session.peerTailscaleIp, '100.64.0.12');
      expect(session.lastSdpOffer, isNull);
      expect(session.deviceToken, 'token123');
      expect(session.cachedAt, DateTime.utc(2026, 3, 28, 10, 0));
    });

    test('round-trip JSON serialization', () {
      final original = CachedSession(
        sessionId: 'sess_003',
        peerTailscaleIp: '100.64.0.50',
        lastSdpOffer: 'offer_sdp',
        lastSdpAnswer: 'answer_sdp',
        deviceToken: 'jwt_token',
        cachedAt: DateTime.utc(2026, 3, 28, 12, 30),
      );

      final json = original.toJson();
      final restored = CachedSession.fromJson(json);

      expect(restored.sessionId, original.sessionId);
      expect(restored.peerTailscaleIp, original.peerTailscaleIp);
      expect(restored.lastSdpOffer, original.lastSdpOffer);
      expect(restored.lastSdpAnswer, original.lastSdpAnswer);
      expect(restored.deviceToken, original.deviceToken);
      expect(restored.cachedAt, original.cachedAt);
    });
  });
}
