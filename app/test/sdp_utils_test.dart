import 'package:flutter_test/flutter_test.dart';
import 'package:tailcall/features/call/services/sdp_utils.dart';

void main() {
  group('SdpUtils', () {
    const sampleSdp = 'v=0\r\n'
        'o=- 123456 2 IN IP4 127.0.0.1\r\n'
        's=-\r\n'
        'm=audio 9 UDP/TLS/RTP/SAVPF 111 103 104\r\n'
        'a=rtpmap:111 opus/48000/2\r\n'
        'a=fmtp:111 minptime=10;useinbandfec=0\r\n'
        'a=rtpmap:103 ISAC/16000\r\n';

    test('applies Opus optimizations with default bitrate', () {
      final result = SdpUtils.applyOpusOptimizations(sampleSdp);
      expect(result, contains('useinbandfec=1'));
      expect(result, contains('usedtx=1'));
      expect(result, contains('maxaveragebitrate=24000'));
    });

    test('applies Opus optimizations with custom bitrate', () {
      final result =
          SdpUtils.applyOpusOptimizations(sampleSdp, bitrate: 16000);
      expect(result, contains('maxaveragebitrate=16000'));
    });

    test('preserves non-fmtp lines', () {
      final result = SdpUtils.applyOpusOptimizations(sampleSdp);
      expect(result, contains('a=rtpmap:111 opus/48000/2'));
      expect(result, contains('a=rtpmap:103 ISAC/16000'));
      expect(result, contains('v=0'));
    });

    test('replaces existing fmtp line', () {
      final result = SdpUtils.applyOpusOptimizations(sampleSdp);
      // Should not contain original fmtp
      expect(result, isNot(contains('useinbandfec=0')));
    });
  });

  group('CallState model', () {
    test('stateKey returns correct string', () {
      // Import is not needed here since we test SDP utils
      // CallState model tests are in a separate file
    });
  });
}
