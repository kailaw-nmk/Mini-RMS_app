import { describe, it, expect } from 'vitest';
import { generateToken, verifyToken, shouldRefresh, refreshToken } from '../src/auth/jwt.js';

describe('JWT', () => {
  const payload = {
    device_id: 'driver_001',
    tailscale_ip: '100.64.0.12',
    role: 'driver',
  };

  it('generates a valid token', () => {
    const token = generateToken(payload);
    expect(token).toBeTruthy();
    expect(typeof token).toBe('string');
    expect(token.split('.')).toHaveLength(3);
  });

  it('verifies a valid token', () => {
    const token = generateToken(payload);
    const result = verifyToken(token);
    expect(result.valid).toBe(true);
    expect(result.payload.device_id).toBe('driver_001');
    expect(result.payload.tailscale_ip).toBe('100.64.0.12');
    expect(result.payload.role).toBe('driver');
  });

  it('rejects an invalid token', () => {
    const result = verifyToken('invalid.token.here');
    expect(result.valid).toBe(false);
    expect(result.error).toBeTruthy();
  });

  it('rejects a tampered token', () => {
    const token = generateToken(payload);
    const tampered = token.slice(0, -5) + 'xxxxx';
    const result = verifyToken(tampered);
    expect(result.valid).toBe(false);
  });

  it('shouldRefresh returns false for fresh tokens', () => {
    const token = generateToken(payload);
    expect(shouldRefresh(token)).toBe(false);
  });

  it('refreshes a valid token', () => {
    const token = generateToken(payload);
    const newToken = refreshToken(token);
    expect(newToken).toBeTruthy();
    // Token is valid and contains the same payload
    const result = verifyToken(newToken);
    expect(result.valid).toBe(true);
    expect(result.payload.device_id).toBe('driver_001');
  });

  it('refresh returns null for invalid token', () => {
    const result = refreshToken('invalid.token');
    expect(result).toBeNull();
  });

  it('includes role in token', () => {
    const operatorToken = generateToken({ ...payload, role: 'operator' });
    const result = verifyToken(operatorToken);
    expect(result.payload.role).toBe('operator');
  });
});
