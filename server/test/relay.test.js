import { describe, it, expect, beforeEach } from 'vitest';
import { registerConnection, unregisterConnection, getConnection, relayMessage, getConnectedDevices } from '../src/ws/relay.js';

// Mock WebSocket
function createMockWs() {
  const messages = [];
  return {
    readyState: 1, // OPEN
    send: (data) => messages.push(JSON.parse(data)),
    messages,
  };
}

describe('Relay', () => {
  beforeEach(() => {
    // Clean up connections
    for (const id of getConnectedDevices()) {
      unregisterConnection(id);
    }
  });

  it('registers and retrieves a connection', () => {
    const ws = createMockWs();
    registerConnection('device_001', ws);
    expect(getConnection('device_001')).toBe(ws);
  });

  it('unregisters a connection', () => {
    const ws = createMockWs();
    registerConnection('device_001', ws);
    unregisterConnection('device_001');
    expect(getConnection('device_001')).toBeUndefined();
  });

  it('relays a message to target', () => {
    const ws = createMockWs();
    registerConnection('device_001', ws);

    const message = { type: 'sdp_offer', session_id: 'sess_001', sdp: 'v=0...' };
    const result = relayMessage('device_001', message);

    expect(result).toBe(true);
    expect(ws.messages).toHaveLength(1);
    expect(ws.messages[0].type).toBe('sdp_offer');
    expect(ws.messages[0].session_id).toBe('sess_001');
  });

  it('returns false when target not connected', () => {
    const message = { type: 'sdp_offer', session_id: 'sess_001' };
    const result = relayMessage('nonexistent', message);
    expect(result).toBe(false);
  });

  it('returns false when target ws is closed', () => {
    const ws = createMockWs();
    ws.readyState = 3; // CLOSED
    registerConnection('device_001', ws);

    const result = relayMessage('device_001', { type: 'sdp_offer' });
    expect(result).toBe(false);
  });

  it('lists connected devices', () => {
    registerConnection('device_001', createMockWs());
    registerConnection('device_002', createMockWs());

    const devices = getConnectedDevices();
    expect(devices).toContain('device_001');
    expect(devices).toContain('device_002');
    expect(devices).toHaveLength(2);
  });
});
