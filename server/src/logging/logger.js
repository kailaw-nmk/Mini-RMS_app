import pino from 'pino';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  name: 'tailcall-signaling',
});

export default logger;
