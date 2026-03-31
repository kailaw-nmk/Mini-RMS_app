import Redis from 'ioredis';
import logger from '../logging/logger.js';

const SESSION_TTL = parseInt(process.env.SESSION_TTL || '1800', 10); // 30 minutes

let redis;

export function getRedis() {
  if (!redis) {
    redis = new Redis(process.env.REDIS_URL || 'redis://localhost:6379', {
      maxRetriesPerRequest: 3,
      retryStrategy(times) {
        const delay = Math.min(times * 200, 5000);
        return delay;
      },
    });
    redis.on('connect', () => logger.info('Redis connected'));
    redis.on('error', (err) => logger.error({ err }, 'Redis error'));
  }
  return redis;
}

export async function createSession(session) {
  const key = `session:${session.session_id}`;
  await getRedis().set(key, JSON.stringify(session), 'EX', SESSION_TTL);
  logger.info({ session_id: session.session_id }, 'Session created');
  return session;
}

export async function getSession(sessionId) {
  const data = await getRedis().get(`session:${sessionId}`);
  return data ? JSON.parse(data) : null;
}

export async function updateSession(sessionId, updates) {
  const session = await getSession(sessionId);
  if (!session) return null;
  const updated = { ...session, ...updates };
  await getRedis().set(`session:${sessionId}`, JSON.stringify(updated), 'EX', SESSION_TTL);
  return updated;
}

export async function deleteSession(sessionId) {
  const result = await getRedis().del(`session:${sessionId}`);
  if (result > 0) {
    logger.info({ session_id: sessionId }, 'Session deleted');
  }
  return result > 0;
}

export async function refreshSessionTTL(sessionId) {
  return await getRedis().expire(`session:${sessionId}`, SESSION_TTL);
}

export async function isRedisHealthy() {
  try {
    const pong = await getRedis().ping();
    return pong === 'PONG';
  } catch {
    return false;
  }
}

export { SESSION_TTL };
