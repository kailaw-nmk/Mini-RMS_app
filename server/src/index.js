import { startServer } from './server.js';
import { getRedis } from './session/redis.js';
import logger from './logging/logger.js';

// Initialize Redis connection
getRedis();

// Start the server
const { httpServer } = startServer();

// Graceful shutdown
function shutdown(signal) {
  logger.info({ signal }, 'Shutting down...');
  httpServer.close(() => {
    getRedis().disconnect();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 5000);
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
