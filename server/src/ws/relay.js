import logger from '../logging/logger.js';

// Maps device_id -> WebSocket connection
const connections = new Map();

export function registerConnection(deviceId, ws) {
  connections.set(deviceId, ws);
  logger.info({ device_id: deviceId }, 'Connection registered');
}

export function unregisterConnection(deviceId) {
  connections.delete(deviceId);
  logger.info({ device_id: deviceId }, 'Connection unregistered');
}

export function getConnection(deviceId) {
  return connections.get(deviceId);
}

export function relayMessage(targetDeviceId, message) {
  const targetWs = connections.get(targetDeviceId);
  if (!targetWs || targetWs.readyState !== 1) {
    logger.warn({ target: targetDeviceId, type: message.type }, 'Relay target not connected');
    return false;
  }
  targetWs.send(JSON.stringify(message));
  logger.debug({ target: targetDeviceId, type: message.type }, 'Message relayed');
  return true;
}

export function getConnectedDevices() {
  return Array.from(connections.keys());
}
