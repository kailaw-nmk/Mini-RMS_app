import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import http from 'node:http';
import WebSocket, { WebSocketServer } from 'ws';
import { generateToken } from '../src/auth/jwt.js';
import { getRedis, isRedisHealthy } from '../src/session/redis.js';
import { handleConnection } from '../src/ws/handler.js';

const PORT = 9091;
let server, wss;

function createWsClient() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${PORT}`);
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

function waitForMessage(ws, type, timeout = 5000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Timeout waiting for ${type}`)), timeout);
    const handler = (data) => {
      const msg = JSON.parse(data.toString());
      if (msg.type === type) {
        clearTimeout(timer);
        ws.removeListener('message', handler);
        resolve(msg);
      }
    };
    ws.on('message', handler);
  });
}

function sendJson(ws, msg) {
  ws.send(JSON.stringify(msg));
}

const OPERATOR_IP = '100.64.0.5';
const DRIVER_IP = '100.64.0.12';

let pairCounter = 0;

/** Helper: connect and auth both peers, driver first */
async function setupCallPair() {
  pairCounter++;
  const opId = `op_${pairCounter}`;
  const drId = `dr_${pairCounter}`;

  const opToken = generateToken({ device_id: opId, tailscale_ip: OPERATOR_IP, role: 'operator' });
  const drToken = generateToken({ device_id: drId, tailscale_ip: DRIVER_IP, role: 'driver' });

  // Driver connects first (so IP mapping exists when operator calls)
  const drWs = await createWsClient();
  sendJson(drWs, { type: 'auth', device_token: drToken, device_id: drId });
  await waitForMessage(drWs, 'auth_result');

  const opWs = await createWsClient();
  sendJson(opWs, { type: 'auth', device_token: opToken, device_id: opId });
  await waitForMessage(opWs, 'auth_result');

  return { opWs, drWs };
}

describe('E2E: Signaling Server', () => {
  beforeAll(async () => {
    const healthy = await isRedisHealthy();
    if (!healthy) throw new Error('Redis not available');

    server = http.createServer();
    wss = new WebSocketServer({ server });
    wss.on('connection', handleConnection);
    await new Promise((resolve) => server.listen(PORT, resolve));
  });

  afterAll(async () => {
    wss?.close();
    server?.close();
    const redis = getRedis();
    const keys = await redis.keys('session:sess_*');
    if (keys.length) await redis.del(...keys);
    redis.disconnect();
  });

  it('T-AUTH: operator authenticates successfully', async () => {
    const opToken = generateToken({ device_id: 'auth_op', tailscale_ip: OPERATOR_IP, role: 'operator' });
    const ws = await createWsClient();
    sendJson(ws, { type: 'auth', device_token: opToken, device_id: 'auth_op' });
    const result = await waitForMessage(ws, 'auth_result');
    expect(result.success).toBe(true);
    ws.close();
  });

  it('T-AUTH: invalid token is rejected', async () => {
    const ws = await createWsClient();
    sendJson(ws, { type: 'auth', device_token: 'bad.token.here', device_id: 'bad' });
    const result = await waitForMessage(ws, 'auth_result');
    expect(result.success).toBe(false);
    ws.close();
  });

  it('T-CALL: operator initiates call, driver receives', async () => {
    const { opWs, drWs } = await setupCallPair();

    sendJson(opWs, {
      type: 'call_initiate', from: OPERATOR_IP, to: DRIVER_IP,
      mode: 'audio', timestamp: new Date().toISOString(),
    });

    const initiated = await waitForMessage(opWs, 'call_initiated');
    expect(initiated.session_id).toBeTruthy();

    const incoming = await waitForMessage(drWs, 'call_initiate');
    expect(incoming.session_id).toBe(initiated.session_id);

    opWs.close();
    drWs.close();
  });

  it('T-RELAY: SDP offer relayed to driver', async () => {
    const { opWs, drWs } = await setupCallPair();

    sendJson(opWs, {
      type: 'call_initiate', from: OPERATOR_IP, to: DRIVER_IP,
      mode: 'audio', timestamp: new Date().toISOString(),
    });
    const initiated = await waitForMessage(opWs, 'call_initiated');
    await waitForMessage(drWs, 'call_initiate');

    sendJson(opWs, {
      type: 'sdp_offer', session_id: initiated.session_id,
      sdp: 'v=0\r\no=- test offer', ice_restart: false,
    });

    const offer = await waitForMessage(drWs, 'sdp_offer');
    expect(offer.sdp).toBe('v=0\r\no=- test offer');

    opWs.close();
    drWs.close();
  });

  it('T-RELAY: SDP answer relayed to operator', async () => {
    const { opWs, drWs } = await setupCallPair();

    sendJson(opWs, {
      type: 'call_initiate', from: OPERATOR_IP, to: DRIVER_IP,
      mode: 'audio', timestamp: new Date().toISOString(),
    });
    const initiated = await waitForMessage(opWs, 'call_initiated');
    await waitForMessage(drWs, 'call_initiate');

    sendJson(drWs, {
      type: 'sdp_answer', session_id: initiated.session_id,
      sdp: 'v=0\r\no=- test answer',
    });

    const answer = await waitForMessage(opWs, 'sdp_answer');
    expect(answer.sdp).toBe('v=0\r\no=- test answer');

    opWs.close();
    drWs.close();
  });

  it('T-ICE: ICE candidates relayed', async () => {
    const { opWs, drWs } = await setupCallPair();

    sendJson(opWs, {
      type: 'call_initiate', from: OPERATOR_IP, to: DRIVER_IP,
      mode: 'audio', timestamp: new Date().toISOString(),
    });
    const initiated = await waitForMessage(opWs, 'call_initiated');
    await waitForMessage(drWs, 'call_initiate');

    sendJson(opWs, {
      type: 'ice_candidate', session_id: initiated.session_id,
      candidate: { candidate: 'candidate:1 1 UDP 2130706431 10.0.0.1 5000 typ host', sdpMid: '0', sdpMLineIndex: 0 },
    });

    const ice = await waitForMessage(drWs, 'ice_candidate');
    expect(ice.candidate.candidate).toContain('candidate:1');

    opWs.close();
    drWs.close();
  });

  it('T-END: call_end relayed and session updated', async () => {
    const { opWs, drWs } = await setupCallPair();

    sendJson(opWs, {
      type: 'call_initiate', from: OPERATOR_IP, to: DRIVER_IP,
      mode: 'audio', timestamp: new Date().toISOString(),
    });
    const initiated = await waitForMessage(opWs, 'call_initiated');
    await waitForMessage(drWs, 'call_initiate');

    sendJson(opWs, {
      type: 'call_end', session_id: initiated.session_id,
      reason: 'operator_hangup', timestamp: new Date().toISOString(),
    });

    const ended = await waitForMessage(drWs, 'call_end');
    expect(ended.reason).toBe('operator_hangup');

    // Verify session state in Redis
    const redis = getRedis();
    const session = await redis.get(`session:${initiated.session_id}`);
    const parsed = JSON.parse(session);
    expect(parsed.state).toBe('DISCONNECTED');

    opWs.close();
    drWs.close();
  });

  it('T-007: session persists after WebSocket disconnect', async () => {
    const { opWs, drWs } = await setupCallPair();

    sendJson(opWs, {
      type: 'call_initiate', from: OPERATOR_IP, to: DRIVER_IP,
      mode: 'audio', timestamp: new Date().toISOString(),
    });
    const initiated = await waitForMessage(opWs, 'call_initiated');
    await waitForMessage(drWs, 'call_initiate');

    const redis = getRedis();
    const before = await redis.get(`session:${initiated.session_id}`);
    expect(before).toBeTruthy();

    // Simulate signaling loss
    opWs.close();
    drWs.close();

    // Session still exists (P2P would continue independently)
    await new Promise(r => setTimeout(r, 200));
    const after = await redis.get(`session:${initiated.session_id}`);
    expect(after).toBeTruthy();
  });
});
