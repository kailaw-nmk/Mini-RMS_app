import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { createPairingCode, confirmPairing } from '../src/auth/pairing.js';
import { verifyToken } from '../src/auth/jwt.js';
import { getRedis, isRedisHealthy } from '../src/session/redis.js';

describe('Pairing', () => {
  beforeAll(async () => {
    const healthy = await isRedisHealthy();
    if (!healthy) {
      throw new Error('Redis is not available');
    }
  });

  afterAll(async () => {
    const redis = getRedis();
    const keys = await redis.keys('pairing:*');
    if (keys.length > 0) {
      await redis.del(...keys);
    }
    redis.disconnect();
  });

  it('creates a 6-digit pairing code', async () => {
    const code = await createPairingCode('operator_hq01');
    expect(code).toMatch(/^\d{6}$/);
  });

  it('confirms pairing and returns JWT', async () => {
    const code = await createPairingCode('operator_hq01');
    const result = await confirmPairing(code, {
      device_id: 'driver_truck042',
      tailscale_ip: '100.64.0.12',
      role: 'driver',
    });

    expect(result.success).toBe(true);
    expect(result.token).toBeTruthy();
    expect(result.operator_device_id).toBe('operator_hq01');

    // Verify the issued JWT
    const verified = verifyToken(result.token);
    expect(verified.valid).toBe(true);
    expect(verified.payload.device_id).toBe('driver_truck042');
    expect(verified.payload.role).toBe('driver');
  });

  it('rejects invalid pairing code', async () => {
    const result = await confirmPairing('000000', {
      device_id: 'driver_truck042',
      tailscale_ip: '100.64.0.12',
    });
    expect(result.success).toBe(false);
    expect(result.error).toBe('INVALID_OR_EXPIRED_CODE');
  });

  it('code can only be used once', async () => {
    const code = await createPairingCode('operator_hq01');

    const first = await confirmPairing(code, {
      device_id: 'driver_001',
      tailscale_ip: '100.64.0.10',
    });
    expect(first.success).toBe(true);

    const second = await confirmPairing(code, {
      device_id: 'driver_002',
      tailscale_ip: '100.64.0.11',
    });
    expect(second.success).toBe(false);
  });
});
