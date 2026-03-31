import { getRedis } from '../session/redis.js';
import { generateToken } from './jwt.js';
import logger from '../logging/logger.js';

const PAIRING_CODE_TTL = 300; // 5 minutes
const PAIRING_KEY_PREFIX = 'pairing:';

function generateCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

export async function createPairingCode(operatorDeviceId) {
  const code = generateCode();
  const key = `${PAIRING_KEY_PREFIX}${code}`;
  await getRedis().set(
    key,
    JSON.stringify({ operator_device_id: operatorDeviceId, created_at: new Date().toISOString() }),
    'EX',
    PAIRING_CODE_TTL
  );
  logger.info({ operator_device_id: operatorDeviceId, code }, 'Pairing code created');
  return code;
}

export async function confirmPairing(code, driverInfo) {
  const key = `${PAIRING_KEY_PREFIX}${code}`;
  const data = await getRedis().get(key);

  if (!data) {
    return { success: false, error: 'INVALID_OR_EXPIRED_CODE' };
  }

  const pairingData = JSON.parse(data);

  // Delete used code
  await getRedis().del(key);

  // Generate JWT for the driver device
  const token = generateToken({
    device_id: driverInfo.device_id,
    tailscale_ip: driverInfo.tailscale_ip,
    role: driverInfo.role || 'driver',
  });

  logger.info(
    { device_id: driverInfo.device_id, operator: pairingData.operator_device_id },
    'Pairing confirmed'
  );

  return {
    success: true,
    token,
    operator_device_id: pairingData.operator_device_id,
  };
}
