require('dotenv').config({ path: 'config/.env' });

/** @type {import('fonzi2').Config} */
module.exports = {
	server: {
		loginData: {
			oauth2url: process.env['OAUTH2_URL'],
			ownerIds: process.env['OWNER_IDS']
				? process.env['OWNER_IDS'].split(',')
				: [],
			redirectRoute: '/dashboard',
		},
		port: process.env['PORT'] || 8080,
	},
	logger: {
		enabled: true,
		levels: 'all',
		remote: {
			enabled: false,
			levels: 'all',
		},
		file: {
			enabled: false,
			levels: 'all',
			path: 'logs/',
		},
	},
};
