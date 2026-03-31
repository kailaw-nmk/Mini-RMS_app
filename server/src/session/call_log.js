import { getRedis } from './redis.js';
import logger from '../logging/logger.js';

const CALL_LOG_KEY = 'call_logs';
const CALL_LOG_TTL = 90 * 24 * 60 * 60; // 90 days in seconds

/**
 * Append a call event to the log
 */
export async function logCallEvent(event) {
  const entry = {
    ...event,
    timestamp: event.timestamp || new Date().toISOString(),
  };

  const redis = getRedis();
  await redis.lpush(CALL_LOG_KEY, JSON.stringify(entry));
  // Trim to 10000 entries max
  await redis.ltrim(CALL_LOG_KEY, 0, 9999);
  logger.debug({ event: entry.event, session_id: entry.session_id }, 'Call event logged');
}

/**
 * Get recent call logs
 * @param {number} limit - Max entries to return
 * @param {number} offset - Offset for pagination
 */
export async function getCallLogs(limit = 50, offset = 0) {
  const redis = getRedis();
  const entries = await redis.lrange(CALL_LOG_KEY, offset, offset + limit - 1);
  return entries.map((e) => JSON.parse(e));
}

/**
 * Get call statistics
 */
export async function getCallStats() {
  const redis = getRedis();
  const allLogs = await redis.lrange(CALL_LOG_KEY, 0, -1);
  const logs = allLogs.map((e) => JSON.parse(e));

  const totalCalls = logs.filter((l) => l.event === 'call_start').length;
  const totalDisconnects = logs.filter((l) => l.event === 'disconnect').length;
  const totalReconnects = logs.filter((l) => l.event === 'reconnect').length;

  // Calculate average disconnect duration
  const disconnectDurations = logs
    .filter((l) => l.event === 'reconnect' && l.reconnect_duration_ms)
    .map((l) => l.reconnect_duration_ms);
  const avgDisconnectMs =
    disconnectDurations.length > 0
      ? disconnectDurations.reduce((a, b) => a + b, 0) / disconnectDurations.length
      : 0;

  return {
    total_calls: totalCalls,
    total_disconnects: totalDisconnects,
    total_reconnects: totalReconnects,
    avg_reconnect_ms: Math.round(avgDisconnectMs),
    log_count: logs.length,
  };
}

/**
 * Get all active sessions
 */
export async function getActiveSessions() {
  const redis = getRedis();
  const keys = await redis.keys('session:sess_*');
  const sessions = [];
  for (const key of keys) {
    const data = await redis.get(key);
    if (data) {
      const session = JSON.parse(data);
      const ttl = await redis.ttl(key);
      sessions.push({ ...session, ttl_remaining: ttl });
    }
  }
  return sessions;
}
