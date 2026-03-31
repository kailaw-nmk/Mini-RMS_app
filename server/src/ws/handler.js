import { v4 as uuidv4 } from 'uuid';
import { verifyToken, shouldRefresh, refreshToken } from '../auth/jwt.js';
import { createSession, getSession, updateSession, refreshSessionTTL } from '../session/redis.js';
import { logCallEvent } from '../session/call_log.js';
import { registerConnection, unregisterConnection, relayMessage } from './relay.js';
import logger from '../logging/logger.js';

// Authenticated device info per WebSocket
const wsAuthMap = new WeakMap();

function sendError(ws, code, message) {
  ws.send(JSON.stringify({ type: 'error', code, message }));
}

function sendMessage(ws, message) {
  if (ws.readyState === 1) {
    ws.send(JSON.stringify(message));
  }
}

async function handleAuth(ws, msg) {
  const result = verifyToken(msg.device_token);
  if (!result.valid) {
    sendMessage(ws, { type: 'auth_result', success: false, error: 'AUTH_FAILED' });
    logger.warn({ device_id: msg.device_id, error: result.error }, 'Auth failed');
    return;
  }

  const { device_id, tailscale_ip, role } = result.payload;
  const authInfo = { device_id, tailscale_ip, role };
  wsAuthMap.set(ws, authInfo);
  registerConnection(device_id, ws);
  ipToDeviceMap.set(tailscale_ip, device_id);

  const response = { type: 'auth_result', success: true, session_resumed: false };

  // Attempt session resume
  if (msg.session_resume_id) {
    const session = await getSession(msg.session_resume_id);
    if (session) {
      response.session_resumed = true;
      response.session_id = session.session_id;
      await refreshSessionTTL(session.session_id);
    }
  }

  // Auto-refresh JWT if close to expiry
  if (shouldRefresh(msg.device_token)) {
    response.new_token = refreshToken(msg.device_token);
  }

  sendMessage(ws, response);
  logger.info({ device_id, role, resumed: response.session_resumed }, 'Auth successful');
}

async function handleCallInitiate(ws, msg) {
  const auth = wsAuthMap.get(ws);
  if (!auth) return sendError(ws, 'UNAUTHORIZED', 'Not authenticated');
  if (auth.role !== 'operator') return sendError(ws, 'UNAUTHORIZED', 'Only operator can initiate calls');

  const sessionId = `sess_${Date.now()}_${uuidv4().slice(0, 8)}`;
  const session = {
    session_id: sessionId,
    operator_device_id: auth.device_id,
    operator_ip: msg.from,
    driver_device_id: ipToDeviceMap.get(msg.to) || null,
    driver_ip: msg.to,
    state: 'CONNECTED',
    mode: msg.mode || 'audio',
    created_at: new Date().toISOString(),
    last_connected_at: new Date().toISOString(),
    disconnect_count: 0,
    total_disconnect_seconds: 0,
  };

  await createSession(session);

  const outMsg = { ...msg, session_id: sessionId };
  const driverDeviceId = session.driver_device_id;
  const relayed = driverDeviceId
    ? relayMessage(driverDeviceId, outMsg)
    : relayToByIp(msg.to, outMsg);

  if (!relayed) {
    sendError(ws, 'PEER_NOT_CONNECTED', 'Target peer is not online');
    return;
  }

  sendMessage(ws, { type: 'call_initiated', session_id: sessionId });
  logCallEvent({ event: 'call_start', session_id: sessionId, operator: auth.device_id, driver_ip: msg.to });
}

function relayToByIp(targetIp, message) {
  const deviceId = ipToDeviceMap.get(targetIp);
  if (deviceId) {
    return relayMessage(deviceId, message);
  }
  return false;
}

// IP to device_id mapping
const ipToDeviceMap = new Map();

function registerIpMapping(ip, deviceId) {
  ipToDeviceMap.set(ip, deviceId);
}

async function handleRelayMessage(ws, msg) {
  const auth = wsAuthMap.get(ws);
  if (!auth) return sendError(ws, 'UNAUTHORIZED', 'Not authenticated');

  if (!msg.session_id) return sendError(ws, 'INVALID_MESSAGE', 'Missing session_id');

  const session = await getSession(msg.session_id);
  if (!session) return sendError(ws, 'SESSION_NOT_FOUND', 'Session does not exist');

  // Determine the target: relay to the other party in the session
  let targetDeviceId;
  if (auth.device_id === session.operator_device_id) {
    targetDeviceId = session.driver_device_id;
  } else {
    targetDeviceId = session.operator_device_id;
  }

  // Also try IP-based lookup as fallback
  if (!targetDeviceId) {
    const targetIp = auth.device_id === session.operator_device_id ? session.driver_ip : session.operator_ip;
    targetDeviceId = ipToDeviceMap.get(targetIp);
  }

  if (!targetDeviceId) {
    return sendError(ws, 'PEER_NOT_CONNECTED', 'Target peer is not online');
  }

  const relayed = relayMessage(targetDeviceId, msg);
  if (!relayed) {
    sendError(ws, 'PEER_NOT_CONNECTED', 'Target peer is not online');
  }

  // Update session and log on state_change
  if (msg.type === 'state_change') {
    await updateSession(msg.session_id, {
      state: msg.to_state,
      last_reconnect_method: msg.reconnect_method,
      last_metrics: msg.metrics,
    });
    if (msg.to_state === 'RECONNECTING_NETWORK' || msg.to_state === 'RECONNECTING_PEER') {
      logCallEvent({ event: 'disconnect', session_id: msg.session_id, from_state: msg.from_state, to_state: msg.to_state });
    } else if (msg.from_state?.startsWith('RECONNECTING') && msg.to_state === 'CONNECTED') {
      logCallEvent({ event: 'reconnect', session_id: msg.session_id, method: msg.reconnect_method, reconnect_duration_ms: msg.reconnect_duration_ms });
    }
  }

  // Refresh TTL on any activity
  await refreshSessionTTL(msg.session_id);
}

async function handleCallEnd(ws, msg) {
  const auth = wsAuthMap.get(ws);
  if (!auth) return sendError(ws, 'UNAUTHORIZED', 'Not authenticated');

  const session = await getSession(msg.session_id);
  if (!session) return sendError(ws, 'SESSION_NOT_FOUND', 'Session does not exist');

  // Relay call_end to the other party
  let targetDeviceId;
  if (auth.device_id === session.operator_device_id) {
    targetDeviceId = session.driver_device_id || ipToDeviceMap.get(session.driver_ip);
  } else {
    targetDeviceId = session.operator_device_id;
  }

  if (targetDeviceId) {
    relayMessage(targetDeviceId, msg);
  }

  // Update session state
  await updateSession(msg.session_id, { state: 'DISCONNECTED' });
  logCallEvent({ event: 'call_end', session_id: msg.session_id, reason: msg.reason });
  logger.info({ session_id: msg.session_id, reason: msg.reason }, 'Call ended');
}

// Relay message types that just forward to the other peer
const RELAY_TYPES = new Set([
  'sdp_offer', 'sdp_answer', 'ice_candidate',
  'ice_restart', 'pc_recreate', 'state_change',
  'video_request',
]);

export function handleMessage(ws, raw) {
  let msg;
  try {
    msg = JSON.parse(raw);
  } catch {
    sendError(ws, 'INVALID_MESSAGE', 'Invalid JSON');
    return;
  }

  if (!msg.type) {
    sendError(ws, 'INVALID_MESSAGE', 'Missing message type');
    return;
  }

  logger.debug({ type: msg.type, device_id: wsAuthMap.get(ws)?.device_id }, 'Message received');

  switch (msg.type) {
    case 'auth':
      return handleAuth(ws, msg);
    case 'call_initiate':
      return handleCallInitiate(ws, msg);
    case 'call_end':
      return handleCallEnd(ws, msg);
    default:
      if (RELAY_TYPES.has(msg.type)) {
        return handleRelayMessage(ws, msg);
      }
      sendError(ws, 'INVALID_MESSAGE', `Unknown message type: ${msg.type}`);
  }
}

export function handleConnection(ws) {
  ws.on('message', (raw) => handleMessage(ws, raw.toString()));
  ws.on('close', () => {
    const auth = wsAuthMap.get(ws);
    if (auth) {
      unregisterConnection(auth.device_id);
      ipToDeviceMap.delete(auth.tailscale_ip);
    }
  });
  ws.on('error', (err) => {
    const auth = wsAuthMap.get(ws);
    logger.error({ err, device_id: auth?.device_id }, 'WebSocket error');
  });
}

// Export for internal use
export { wsAuthMap, ipToDeviceMap, registerIpMapping };
