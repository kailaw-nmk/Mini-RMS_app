/// Default signaling server address (Tailscale IP)
const String kDefaultSignalingUrl = 'ws://100.64.0.50:8080';

/// Connection state display names (Japanese)
const Map<String, String> kStateDisplayNames = {
  'CONNECTED': '接続中',
  'RECONNECTING_NETWORK': '再接続中（圏外）',
  'RECONNECTING_PEER': '再接続中（相手）',
  'SUSPENDED': '接続待機中',
  'DISCONNECTED': '切断',
};

/// Connection state colors (as hex values)
const Map<String, int> kStateColors = {
  'CONNECTED': 0xFF4CAF50, // Green
  'RECONNECTING_NETWORK': 0xFFFFEB3B, // Yellow
  'RECONNECTING_PEER': 0xFFFFEB3B, // Yellow
  'SUSPENDED': 0xFFFF9800, // Orange
  'DISCONNECTED': 0xFF9E9E9E, // Gray
};
