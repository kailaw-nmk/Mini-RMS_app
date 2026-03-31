import http from 'node:http';
import { WebSocketServer } from 'ws';
import { verifyToken } from './auth/jwt.js';
import { createPairingCode, confirmPairing } from './auth/pairing.js';
import { isRedisHealthy } from './session/redis.js';
import { getActiveSessions, getCallLogs, getCallStats } from './session/call_log.js';
import { handleConnection } from './ws/handler.js';
import { getConnectedDevices } from './ws/relay.js';
import logger from './logging/logger.js';

const PORT = parseInt(process.env.PORT || '8080', 10);

function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch {
        reject(new Error('Invalid JSON body'));
      }
    });
    req.on('error', reject);
  });
}

function sendJson(res, status, data) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

function extractAuth(req) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) return null;
  return verifyToken(authHeader.slice(7));
}

async function handleRequest(req, res) {
  const { method, url } = req;

  // CORS headers for all requests
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (method === 'OPTIONS') {
    res.writeHead(204);
    return res.end();
  }

  // Health check
  if (method === 'GET' && url === '/api/health') {
    const redisOk = await isRedisHealthy();
    const status = redisOk ? 200 : 503;
    return sendJson(res, status, {
      status: redisOk ? 'healthy' : 'degraded',
      redis: redisOk ? 'connected' : 'disconnected',
      uptime: process.uptime(),
    });
  }

  // Generate pairing code (operator only)
  if (method === 'POST' && url === '/api/pair') {
    const auth = extractAuth(req);
    if (!auth || !auth.valid) {
      return sendJson(res, 401, { error: 'AUTH_FAILED', message: 'Invalid or missing token' });
    }
    if (auth.payload.role !== 'operator') {
      return sendJson(res, 403, { error: 'UNAUTHORIZED', message: 'Only operator can create pairing codes' });
    }
    const code = await createPairingCode(auth.payload.device_id);
    return sendJson(res, 200, { code, expires_in: 300 });
  }

  // Confirm pairing (driver provides code + device info)
  if (method === 'POST' && url === '/api/pair/confirm') {
    try {
      const body = await parseBody(req);
      if (!body.code || !body.device_id || !body.tailscale_ip) {
        return sendJson(res, 400, { error: 'INVALID_MESSAGE', message: 'Missing code, device_id, or tailscale_ip' });
      }
      const result = await confirmPairing(body.code, {
        device_id: body.device_id,
        tailscale_ip: body.tailscale_ip,
        role: body.role || 'driver',
      });
      if (!result.success) {
        return sendJson(res, 400, { error: result.error, message: 'Invalid or expired pairing code' });
      }
      return sendJson(res, 200, { token: result.token, operator_device_id: result.operator_device_id });
    } catch (err) {
      return sendJson(res, 400, { error: 'INVALID_MESSAGE', message: err.message });
    }
  }

  // === Dashboard API (operator only) ===

  // Get active sessions
  if (method === 'GET' && url === '/api/sessions') {
    const auth = extractAuth(req);
    if (!auth || !auth.valid) {
      return sendJson(res, 401, { error: 'AUTH_FAILED' });
    }
    const sessions = await getActiveSessions();
    const connected = getConnectedDevices();
    return sendJson(res, 200, { sessions, connected_devices: connected });
  }

  // Get call logs
  if (method === 'GET' && (url === '/api/logs' || url?.startsWith('/api/logs?'))) {
    const auth = extractAuth(req);
    if (!auth || !auth.valid) {
      return sendJson(res, 401, { error: 'AUTH_FAILED' });
    }
    const params = new URL(url, 'http://localhost').searchParams;
    const limit = parseInt(params.get('limit') || '50', 10);
    const offset = parseInt(params.get('offset') || '0', 10);
    const logs = await getCallLogs(limit, offset);
    return sendJson(res, 200, { logs, limit, offset });
  }

  // Get call statistics
  if (method === 'GET' && url === '/api/stats') {
    const auth = extractAuth(req);
    if (!auth || !auth.valid) {
      return sendJson(res, 401, { error: 'AUTH_FAILED' });
    }
    const stats = await getCallStats();
    return sendJson(res, 200, stats);
  }

  sendJson(res, 404, { error: 'NOT_FOUND', message: 'Endpoint not found' });
}

export function startServer() {
  const httpServer = http.createServer(handleRequest);
  const wss = new WebSocketServer({ server: httpServer });

  wss.on('connection', (ws) => {
    handleConnection(ws);
  });

  httpServer.listen(PORT, () => {
    logger.info({ port: PORT }, 'TailCall signaling server started');
  });

  return { httpServer, wss };
}
