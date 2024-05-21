import { config } from 'dotenv';

config({ path: 'config/.env' });

const env = {
	TOKEN: process.env.TOKEN!,
	OAUTH2_URL: process.env['OAUTH2_URL']!,
	INVITE_LINK: process.env['INVITE_LINK']!,
	LOG_WEBHOOK: process.env['LOG_WEBHOOK'],
	OWNER_IDS: process.env['OWNER_IDS']?.split(',') || [],
	VERSION: process.env['npm_package_version']!,
	PORT: Number(process.env['PORT']) || 8080,
	NODE_ENV: process.env['NODE_ENV'] || 'development',

	MONGODB_URI: process.env['MONGODB_URI']!,
} as const;

export default env;
