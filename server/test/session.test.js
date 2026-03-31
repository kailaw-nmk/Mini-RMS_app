import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { createSession, getSession, updateSession, deleteSession, getRedis, isRedisHealthy } from '../src/session/redis.js';

describe('Session Management', () => {
  beforeAll(async () => {
    // Ensure Redis is available
    const healthy = await isRedisHealthy();
    if (!healthy) {
      throw new Error('Redis is not available. Start it with: docker start tailcall-redis');
    }
  });

  beforeEach(async () => {
    // Clean up test sessions
    const redis = getRedis();
    const keys = await redis.keys('session:test_*');
    if (keys.length > 0) {
      await redis.del(...keys);
    }
  });

  afterAll(async () => {
    const redis = getRedis();
    const keys = await redis.keys('session:test_*');
    if (keys.length > 0) {
      await redis.del(...keys);
    }
    redis.disconnect();
  });

  const testSession = {
    session_id: 'test_sess_001',
    operator_device_id: 'operator_hq01',
    operator_ip: '100.64.0.5',
    driver_device_id: 'driver_truck042',
    driver_ip: '100.64.0.12',
    state: 'CONNECTED',
    mode: 'audio',
    created_at: new Date().toISOString(),
    last_connected_at: new Date().toISOString(),
    disconnect_count: 0,
    total_disconnect_seconds: 0,
  };

  it('creates a session', async () => {
    const session = await createSession(testSession);
    expect(session.session_id).toBe('test_sess_001');
  });

  it('gets a session', async () => {
    await createSession(testSession);
    const session = await getSession('test_sess_001');
    expect(session).not.toBeNull();
    expect(session.session_id).toBe('test_sess_001');
    expect(session.state).toBe('CONNECTED');
    expect(session.operator_device_id).toBe('operator_hq01');
    expect(session.driver_device_id).toBe('driver_truck042');
  });

  it('returns null for non-existent session', async () => {
    const session = await getSession('non_existent');
    expect(session).toBeNull();
  });

  it('updates a session', async () => {
    await createSession(testSession);
    const updated = await updateSession('test_sess_001', {
      state: 'RECONNECTING_NETWORK',
      disconnect_count: 1,
    });
    expect(updated.state).toBe('RECONNECTING_NETWORK');
    expect(updated.disconnect_count).toBe(1);
    expect(updated.operator_device_id).toBe('operator_hq01'); // unchanged fields preserved
  });

  it('update returns null for non-existent session', async () => {
    const result = await updateSession('non_existent', { state: 'DISCONNECTED' });
    expect(result).toBeNull();
  });

  it('deletes a session', async () => {
    await createSession(testSession);
    const deleted = await deleteSession('test_sess_001');
    expect(deleted).toBe(true);
    const session = await getSession('test_sess_001');
    expect(session).toBeNull();
  });

  it('delete returns false for non-existent session', async () => {
    const deleted = await deleteSession('non_existent');
    expect(deleted).toBe(false);
  });

  it('session has TTL set', async () => {
    await createSession(testSession);
    const redis = getRedis();
    const ttl = await redis.ttl('session:test_sess_001');
    expect(ttl).toBeGreaterThan(0);
    expect(ttl).toBeLessThanOrEqual(1800);
  });

  it('redis health check returns true when connected', async () => {
    const healthy = await isRedisHealthy();
    expect(healthy).toBe(true);
  });
});
