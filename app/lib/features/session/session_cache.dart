import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Client-side session cache for signaling server failure fallback.
/// Stores session info locally so reconnection can proceed
/// even when the signaling server is down.
class SessionCache {
  static const _key = 'tailcall_cached_session';
  static const _cacheTtl = Duration(minutes: 30);

  /// Save session info to local cache
  static Future<void> save(CachedSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(session.toJson()));
    debugPrint('SessionCache: saved session ${session.sessionId}');
  }

  /// Load cached session (returns null if expired or not found)
  static Future<CachedSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) return null;

    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final session = CachedSession.fromJson(data);

      // Check TTL
      if (DateTime.now().difference(session.cachedAt) > _cacheTtl) {
        debugPrint('SessionCache: expired, clearing');
        await clear();
        return null;
      }

      return session;
    } catch (e) {
      debugPrint('SessionCache: failed to load: $e');
      await clear();
      return null;
    }
  }

  /// Clear the cached session
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// Cached session data
class CachedSession {
  final String sessionId;
  final String peerTailscaleIp;
  final String? lastSdpOffer;
  final String? lastSdpAnswer;
  final String deviceToken;
  final DateTime cachedAt;

  const CachedSession({
    required this.sessionId,
    required this.peerTailscaleIp,
    this.lastSdpOffer,
    this.lastSdpAnswer,
    required this.deviceToken,
    required this.cachedAt,
  });

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'peer_tailscale_ip': peerTailscaleIp,
        'last_sdp_offer': lastSdpOffer,
        'last_sdp_answer': lastSdpAnswer,
        'device_token': deviceToken,
        'cached_at': cachedAt.toIso8601String(),
      };

  factory CachedSession.fromJson(Map<String, dynamic> json) => CachedSession(
        sessionId: json['session_id'] as String,
        peerTailscaleIp: json['peer_tailscale_ip'] as String,
        lastSdpOffer: json['last_sdp_offer'] as String?,
        lastSdpAnswer: json['last_sdp_answer'] as String?,
        deviceToken: json['device_token'] as String,
        cachedAt: DateTime.parse(json['cached_at'] as String),
      );
}
