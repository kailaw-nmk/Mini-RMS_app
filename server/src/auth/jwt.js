import jwt from 'jsonwebtoken';
import logger from '../logging/logger.js';

const JWT_SECRET = process.env.JWT_SECRET || 'tailcall-dev-secret-change-in-production';
const JWT_EXPIRY = '30d';
const REFRESH_THRESHOLD_DAYS = 7;

export function generateToken(payload) {
  const token = jwt.sign(
    {
      device_id: payload.device_id,
      tailscale_ip: payload.tailscale_ip,
      role: payload.role,
    },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRY }
  );
  logger.info({ device_id: payload.device_id, role: payload.role }, 'JWT generated');
  return token;
}

export function verifyToken(token) {
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    return { valid: true, payload: decoded };
  } catch (err) {
    return { valid: false, error: err.message };
  }
}

export function shouldRefresh(token) {
  try {
    const decoded = jwt.decode(token);
    if (!decoded || !decoded.exp) return false;
    const now = Math.floor(Date.now() / 1000);
    const daysUntilExpiry = (decoded.exp - now) / 86400;
    return daysUntilExpiry < REFRESH_THRESHOLD_DAYS;
  } catch {
    return false;
  }
}

export function refreshToken(token) {
  const result = verifyToken(token);
  if (!result.valid) return null;
  const { device_id, tailscale_ip, role } = result.payload;
  return generateToken({ device_id, tailscale_ip, role });
}

export { JWT_SECRET };
