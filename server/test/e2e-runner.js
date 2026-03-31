/**
 * E2E Test Runner - runs outside vitest to avoid module isolation issues
 * Usage: node test/e2e-runner.js
 */
import http from 'node:http';
import WebSocket, { WebSocketServer } from 'ws';
import { handleConnection } from '../src/ws/handler.js';
import { generateToken } from '../src/auth/jwt.js';
import { getRedis, isRedisHealthy } from '../src/session/redis.js';

const PORT = 9093;
let passed = 0;
let failed = 0;

function assert(condition, msg) {
  if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

function createWs() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${PORT}`);
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

function waitMsg(ws, type, timeout = 5000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Timeout: ${type}`)), timeout);
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

async function setupPair(n) {
  const opId = `op${n}`, drId = `dr${n}`;
  const opToken = generateToken({ device_id: opId, tailscale_ip: '100.64.0.5', role: 'operator' });
  const drToken = generateToken({ device_id: drId, tailscale_ip: '100.64.0.12', role: 'driver' });

  const drWs = await createWs();
  drWs.send(JSON.stringify({ type: 'auth', device_token: drToken, device_id: drId }));
  await waitMsg(drWs, 'auth_result');

  const opWs = await createWs();
  opWs.send(JSON.stringify({ type: 'auth', device_token: opToken, device_id: opId }));
  await waitMsg(opWs, 'auth_result');

  return { opWs, drWs };
}

async function initiateCall(opWs, drWs) {
  // Start listening BEFORE sending to avoid race condition
  const initiatedPromise = waitMsg(opWs, 'call_initiated');
  const incomingPromise = waitMsg(drWs, 'call_initiate');

  opWs.send(JSON.stringify({
    type: 'call_initiate', from: '100.64.0.5', to: '100.64.0.12',
    mode: 'audio', timestamp: new Date().toISOString(),
  }));

  const [initiated, incoming] = await Promise.all([initiatedPromise, incomingPromise]);
  return { initiated, incoming };
}

async function runTest(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`  ✓ ${name}`);
  } catch (e) {
    failed++;
    console.log(`  ✗ ${name}: ${e.message}`);
  }
}

async function main() {
  const healthy = await isRedisHealthy();
  if (!healthy) { console.log('Redis not available!'); process.exit(1); }

  const server = http.createServer();
  const wss = new WebSocketServer({ server });
  wss.on('connection', handleConnection);
  await new Promise(r => server.listen(PORT, r));
  console.log(`E2E test server on port ${PORT}\n`);

  // T-AUTH: valid auth
  await runTest('T-AUTH: valid operator auth', async () => {
    const token = generateToken({ device_id: 'auth_op', tailscale_ip: '100.64.0.5', role: 'operator' });
    const ws = await createWs();
    ws.send(JSON.stringify({ type: 'auth', device_token: token, device_id: 'auth_op' }));
    const r = await waitMsg(ws, 'auth_result');
    assert(r.success === true, 'auth should succeed');
    ws.close();
  });

  // T-AUTH: invalid token
  await runTest('T-AUTH: invalid token rejected', async () => {
    const ws = await createWs();
    ws.send(JSON.stringify({ type: 'auth', device_token: 'bad.token', device_id: 'x' }));
    const r = await waitMsg(ws, 'auth_result');
    assert(r.success === false, 'auth should fail');
    ws.close();
  });

  // T-CALL: initiate
  await runTest('T-CALL: operator initiates, driver receives', async () => {
    const { opWs, drWs } = await setupPair(1);
    const { initiated, incoming } = await initiateCall(opWs, drWs);
    assert(initiated.session_id, 'should have session_id');
    assert(incoming.session_id === initiated.session_id, 'session_id should match');
    opWs.close(); drWs.close();
  });

  // T-RELAY: SDP offer
  await runTest('T-RELAY: SDP offer relayed', async () => {
    const { opWs, drWs } = await setupPair(2);
    const { initiated } = await initiateCall(opWs, drWs);
    opWs.send(JSON.stringify({
      type: 'sdp_offer', session_id: initiated.session_id,
      sdp: 'v=0\r\no=- test', ice_restart: false,
    }));
    const offer = await waitMsg(drWs, 'sdp_offer');
    assert(offer.sdp === 'v=0\r\no=- test', 'sdp should match');
    opWs.close(); drWs.close();
  });

  // T-RELAY: SDP answer
  await runTest('T-RELAY: SDP answer relayed', async () => {
    const { opWs, drWs } = await setupPair(3);
    const { initiated } = await initiateCall(opWs, drWs);
    drWs.send(JSON.stringify({
      type: 'sdp_answer', session_id: initiated.session_id,
      sdp: 'v=0\r\no=- answer',
    }));
    const answer = await waitMsg(opWs, 'sdp_answer');
    assert(answer.sdp === 'v=0\r\no=- answer', 'sdp should match');
    opWs.close(); drWs.close();
  });

  // T-ICE: candidate relay
  await runTest('T-ICE: ICE candidate relayed', async () => {
    const { opWs, drWs } = await setupPair(4);
    const { initiated } = await initiateCall(opWs, drWs);
    opWs.send(JSON.stringify({
      type: 'ice_candidate', session_id: initiated.session_id,
      candidate: { candidate: 'candidate:1 UDP', sdpMid: '0', sdpMLineIndex: 0 },
    }));
    const ice = await waitMsg(drWs, 'ice_candidate');
    assert(ice.candidate.candidate === 'candidate:1 UDP', 'candidate should match');
    opWs.close(); drWs.close();
  });

  // T-END: call end
  await runTest('T-END: call_end relayed + session updated', async () => {
    const { opWs, drWs } = await setupPair(5);
    const { initiated } = await initiateCall(opWs, drWs);
    opWs.send(JSON.stringify({
      type: 'call_end', session_id: initiated.session_id,
      reason: 'operator_hangup', timestamp: new Date().toISOString(),
    }));
    const ended = await waitMsg(drWs, 'call_end');
    assert(ended.reason === 'operator_hangup', 'reason should match');
    // Wait for async Redis update
    await new Promise(r => setTimeout(r, 200));
    const redis = getRedis();
    const sess = JSON.parse(await redis.get(`session:${initiated.session_id}`));
    assert(sess.state === 'DISCONNECTED', 'session should be DISCONNECTED');
    opWs.close(); drWs.close();
  });

  // T-007: session persists
  await runTest('T-007: session persists after WS disconnect', async () => {
    const { opWs, drWs } = await setupPair(6);
    const { initiated } = await initiateCall(opWs, drWs);
    const redis = getRedis();
    const before = await redis.get(`session:${initiated.session_id}`);
    assert(before, 'session should exist before');
    opWs.close(); drWs.close();
    await new Promise(r => setTimeout(r, 300));
    const after = await redis.get(`session:${initiated.session_id}`);
    assert(after, 'session should persist after WS close');
  });

  // Summary
  console.log(`\nResults: ${passed} passed, ${failed} failed, ${passed + failed} total`);

  // Cleanup
  wss.close();
  server.close();
  const redis = getRedis();
  const keys = await redis.keys('session:sess_*');
  if (keys.length) await redis.del(...keys);
  redis.disconnect();
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(e => { console.error(e); process.exit(1); });
