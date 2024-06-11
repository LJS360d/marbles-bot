import 'dotenv/config';

const env = {
  DEV: process.env.NODE_ENV === 'development',
  PROD: process.env.NODE_ENV === 'production',
  NODE_ENV: process.env.NODE_ENV!,
  PORT: Number(process.env.PORT) || 8008,
} as const;

export default env;
