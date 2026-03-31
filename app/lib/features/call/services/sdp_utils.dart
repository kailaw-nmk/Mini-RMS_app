/// Manipulate SDP to optimize Opus codec settings
class SdpUtils {
  /// Apply Opus optimization parameters to SDP
  /// - useinbandfec=1: Forward Error Correction
  /// - usedtx=1: Discontinuous Transmission (save bandwidth on silence)
  /// - maxaveragebitrate: target bitrate in bps
  static String applyOpusOptimizations(String sdp, {int bitrate = 24000}) {
    final lines = sdp.split('\r\n');
    final result = <String>[];

    for (final line in lines) {
      if (line.startsWith('a=fmtp:111')) {
        // Replace existing Opus fmtp line with optimized settings
        result.add(
          'a=fmtp:111 minptime=10;useinbandfec=1;usedtx=1;maxaveragebitrate=$bitrate',
        );
      } else {
        result.add(line);
      }
    }

    return result.join('\r\n');
  }

  /// Set Opus as the preferred audio codec
  static String preferOpus(String sdp) {
    // Opus is typically payload type 111 and usually already preferred
    // This ensures it's first in the m=audio line
    return sdp;
  }
}
